#!/usr/bin/env python3
"""
BERTopic pipeline for the 2025 Ontario Election news corpus.

Python/BERTopic counterpart to R_Scripts/5_key_atm_analysis.R. Where that
script uses keyATM (a seeded LDA variant) on a quanteda dfm, this script
uses BERTopic (MPNet sentence embeddings -> UMAP -> HDBSCAN -> c-TF-IDF) on
the raw article text. It also re-implements, in Python, the corpus
construction steps that the R pipeline does across
2_create_corpus.R / 3_editor&duplicates.R / 4_dictionary.R, because BERTopic
needs raw text rather than a quanteda dfm:

  1. Load data/articles.csv, drop rows with no usable text.
  2. Fix the "missing space after period" OCR artifact.
  3. Drop ProQuest page-image junk docs and letters-to-the-editor.
  4. Deduplicate: same-title/same-paper/<=2-days, then TF-IDF cosine >=0.85
     within week blocks (same-paper only) -- mirrors 3_editor&duplicates.R.
  5. Clean `origin` into a canonical newspaper name (same CANON table as
     4_dictionary.R / 5_key_atm_analysis.R).
  6. Parse `dates`, patch known OCR-corrupted years, flag anything new.
  7. Filter to Ontario-election coverage (vs. federal-only) using the same
     context-gated "ford" + Ontario/federal signal-word logic as
     2_create_corpus.R.
  8. Build a seed_topic_list from the same 7 keyword categories as
     5_key_atm_analysis.R (immigration excluded, matching that script).
  9. Embed with sentence-transformers (default: all-mpnet-base-v2).
 10. Fit BERTopic, guided by the seed keywords.
 11. Save a keyword-frequency plot (~ visualize_keywords), a topic-size
     plot (~ plot_topicprop), a per-newspaper breakdown
     (~ by_strata_DocTopic, via topics_per_class), and a weekly trend
     (~ plot_timetrend, via topics_over_time).

IMPORTANT DIFFERENCE FROM keyATM: seed_topic_list only *nudges* BERTopic
toward your keywords (via embedding similarity + an IDF boost) -- unlike
keyATM's Dirichlet-prior keyword topics, it is not a hard constraint, and
BERTopic gives no posterior/credible intervals. After fitting, inspect
`topic_model.get_topic_info()` yourself and confirm which numeric topic IDs
actually correspond to your seeded categories before trusting any
downstream label -- see the "SUGGESTED (unverified) topic labels" printout
below, and the TODO block right after it.

Setup:
    pip install bertopic sentence-transformers scikit-learn pandas numpy \
        matplotlib kaleido

Usage:
    # Test on a small random sample first -- confirm the preprocessing
    # counts look sane and the plots come out before spending time/compute
    # embedding the full ~16.5k-article corpus.
    python bertopic_topic_analysis.py --sample 300

    # The real run.
    python bertopic_topic_analysis.py

    # Re-run topic modeling only, reusing cached embeddings from a prior run
    # with the same document set (skips re-embedding, which is the slow part).
    python bertopic_topic_analysis.py --use-cache
"""
from __future__ import annotations

import argparse
import hashlib
import re
import sys
from pathlib import Path

import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parent
DATA_CSV = ROOT / "data" / "articles.csv"
DATA_DIR = ROOT / "data"
PLOTS_DIR = ROOT / "Plots"
ARTICLES_DIR = ROOT / "articles"  # BERTopic-methodology citation PDFs, NOT corpus data
CACHE_DIR = ROOT / "data" / "bertopic_cache"

# ---------------------------------------------------------------------------
# Section 5/6 (R): canonical newspaper names and OCR date fixes.
# Identical to the CANON table in R_Scripts/4_dictionary.R and
# R_Scripts/5_key_atm_analysis.R.
# ---------------------------------------------------------------------------
CANON = {
    "globeandmail": "The Globe and Mail",
    "ottawacitizen": "The Ottawa Citizen",
    "ottawasun": "The Ottawa Sun",
    "torontostar": "Toronto Star",
    "torontosun": "The Toronto Sun",
    "windsorstar": "The Windsor Star",
    "hamiltonspectator": "The Hamilton Spectator",
    "spectator": "The Hamilton Spectator",
    "nationalpost": "National Post",
    "saultstar": "Sault Star",
    "sudburystar": "Sudbury Star",
    "kingstonwhigstandard": "Kingston Whig-Standard",
    "standard": "The Standard",
}

# Same "paper family" ids as R_Scripts/3_editor&duplicates.R (print + online
# editions of one outlet collapse to one id for dedup purposes).
def paper_family(raw_origin: str) -> str:
    x = re.sub(r"\s", "", str(raw_origin)).lower()
    families = [
        ("globeandmail", "globe"), ("nationalpost", "natpost"),
        ("torontostar", "star"), ("spectator", "hamspec"),
        ("torontosun", "torsun"), ("ottawasun", "ottsun"),
        ("ottawacitizen", "ottcitizen"), ("saultstar", "saultstar"),
        ("windsorstar", "windsorstar"), ("londonfreepress", "lfp"),
        ("sudburystar", "sudburystar"), ("whig", "kingstonwhig"),
        ("standard", "stcstandard"),  # after whig, so Whig-Standard wins
        ("record", "record"),
    ]
    for needle, fam in families:
        if needle in x:
            return fam
    base = re.sub(r"\(online\)|\(2011-\)|[^\w;]", "", x)
    return base.split(";")[0]


# Known OCR-corrupted years, carried over from R_Scripts/5_key_atm_analysis.R.
# Extend this if the diagnostics below print new unparseable/out-of-range dates.
DATE_FIXES = {
    "0002-06-03": "2024-06-03",
    "0020-02-24": "2025-02-24",
    "0020-05-11": "2024-05-11",
    "0202-01-04": "2024-01-04",
}
DATE_RANGE = (pd.Timestamp("2023-06-01"), pd.Timestamp("2025-12-31"))

# ---------------------------------------------------------------------------
# Section 3 (R, 2_create_corpus.R): Ontario-vs-federal signal words.
# Re-implemented as word-boundary regexes over raw lowercased text rather
# than quanteda tokens_lookup on a stopword-stripped token stream -- close
# in spirit, but not byte-for-byte identical to the R result. Spot-check
# (see check_ontario_filter()) before trusting it on the full corpus.
# ---------------------------------------------------------------------------
FORD_RE = re.compile(r"\bford\b")
CONTEXT_RES = [re.compile(p) for p in
               [r"\bdoug\b", r"\bpremier\b", r"\bqueen'?s park\b", r"\bontario\b"]]
ON_REST_RES = [re.compile(p) for p in [
    r"\bcrombie\b", r"\bstiles\b", r"\bschreiner\b",
    r"\bontario pc\w*\b", r"\bontario liberal\w*\b", r"\bontario ndp\b",
    r"\bontario green\w*\b", r"\bontario election\b", r"\bontario premier\b",
]]
FED_RES = [re.compile(p) for p in [
    r"\bcarney\b", r"\btrudeau\b", r"\bpoilievre\b", r"\bfreeland\b",
    r"\bgould\b", r"\bbaylis\b", r"\bdhalla\b", r"\bjagmeet\b",
    r"\bsingh\b", r"\bblanchet\b", r"\bprime minister\b",
]]


def _count(patterns, text: str) -> int:
    return sum(len(p.findall(text)) for p in patterns)


def is_ontario_article(text_lower: str) -> bool:
    ford_count = len(FORD_RE.findall(text_lower))
    context_count = _count(CONTEXT_RES, text_lower)
    ford_valid = ford_count if context_count > 0 else 0
    on_combined = _count(ON_REST_RES, text_lower) + ford_valid
    fed_count = _count(FED_RES, text_lower)
    return on_combined > fed_count


# ---------------------------------------------------------------------------
# Section 8 (R, 5_key_atm_analysis.R keywords list): seed topics for BERTopic.
# Kept as natural phrases (BERTopic embeds them directly -- no need to
# pre-compound multi-word phrases the way the dfm-based keyATM model does).
# Same 7 categories as the R script; immigration stays commented out to match.
# ---------------------------------------------------------------------------
SEED_TOPIC_LIST = [
    ["housing", "rent", "rents", "renter", "landlord", "affordability",
     "homebuilding", "homebuilder", "apartment", "apartments", "encampment",
     "house", "permit", "zoning", "tenant", "mortgage", "homeless", "condo",
     "nimby", "housing affordability"],
    ["tariff", "tariffs", "trade", "protectionist", "countervailing", "buy",
     "countervail", "buy canadian", "buy american"],
    ["tax", "taxes", "taxation", "taxpayer", "hst"],
    ["health care", "healthcare", "hospital", "doctor", "physician",
     "primary care", "nurse", "nursing", "hospitals", "dr", "ohip", "surgery"],
    ["education", "school", "teacher", "classroom", "teachers", "curriculum",
     "kindergarten", "schools", "students"],
    ["post secondary", "post-secondary", "postsecondary", "university",
     "college", "colleges", "tuition", "professor", "opseu", "campus",
     "universities", "osap", "student"],
    ["crime", "crimes", "criminal", "police", "policing", "theft", "shooting",
     "homicide", "murder", "violence", "bail", "carjacking", "gang",
     "violent", "prison"],
    # ["immigration", "immigrant", "migrant", "refugee", "asylum", "newcomer",
    #  "deportation", "visa", "immigrants", "newcomers"],
]
SEED_LABELS = ["housing", "tariffs_trade", "taxes", "health_care",
               "education", "post_secondary", "crime"]


# ---------------------------------------------------------------------------
# 1. Load + basic text cleanup
# ---------------------------------------------------------------------------
def load_articles(path: Path) -> pd.DataFrame:
    df = pd.read_csv(path)
    df = df.drop(columns=[c for c in df.columns if c.startswith("Unnamed")],
                 errors="ignore")
    n0 = len(df)
    usable = df["text"].notna() & ~df["text"].astype(str).str.strip().isin(
        ["", "Not available."])
    df = df.loc[usable].copy()
    print(f"Loaded {n0} rows, kept {len(df)} with usable text "
          f"({n0 - len(df)} empty/NaN/'Not available.' dropped).")

    # Fix missing space after a sentence-ending period (same regex as
    # 2_create_corpus.R's "Fix spacing artifact" step).
    df["text"] = df["text"].astype(str).str.replace(
        r"([a-z])\.([A-Z])", r"\1. \2", regex=True)
    return df


# ---------------------------------------------------------------------------
# 2. Junk pages + letters-to-the-editor (3_editor&duplicates.R, stages A-B)
# ---------------------------------------------------------------------------
def drop_junk_and_letters(df: pd.DataFrame) -> pd.DataFrame:
    titles = df["titles"].fillna("")
    is_junk = titles.str.match(r"^\s*\w+ \d{1,2}, \d{4} \(Page ")

    section = df["section"].fillna("").str.replace(r"\s", "", regex=True)
    letter_sec = section.str.contains("letter", case=False)
    letter_ttl = titles.str.contains(
        r"^\s*letters?\b.*(?:editor|:)|letters to the editor",
        case=False, regex=True)
    is_letter = letter_sec | letter_ttl

    print(f"Dropping {int(is_junk.sum())} ProQuest page-image junk docs, "
          f"{int(is_letter.sum())} letters-to-the-editor.")
    return df.loc[~(is_junk | is_letter)].copy()


# ---------------------------------------------------------------------------
# 3. Origin cleanup + dates (needed before dedup, since dedup blocks by week
#    and by paper family)
# ---------------------------------------------------------------------------
def clean_origin_and_dates(df: pd.DataFrame) -> pd.DataFrame:
    raw_origin = df["origin"].fillna("")
    key = (raw_origin.str.extract(r"^([^;(]+)", expand=False).fillna("")
           .str.strip()
           .str.replace(r"[^A-Za-z]", "", regex=True)
           .str.lower()
           .str.replace(r"^the", "", regex=True))
    df["origin_clean"] = key.map(CANON).fillna("Other")
    df["is_online"] = raw_origin.str.contains("online", case=False)
    df["paper_family"] = raw_origin.map(paper_family)

    date_chr = df["dates"].astype(str)
    date_chr = date_chr.replace(DATE_FIXES)
    parsed = pd.to_datetime(date_chr, format="%Y-%m-%d", errors="coerce")
    # A couple of alternate formats show up in ProQuest exports; fall back
    # for anything the strict ISO parse missed.
    still_bad = parsed.isna()
    if still_bad.any():
        parsed.loc[still_bad] = pd.to_datetime(
            date_chr.loc[still_bad], errors="coerce", format="mixed")
    df["date"] = parsed

    unparsed = df["date"].isna()
    out_of_range = (~unparsed) & ((df["date"] < DATE_RANGE[0]) |
                                   (df["date"] > DATE_RANGE[1]))
    if unparsed.any():
        bad_vals = sorted(date_chr.loc[unparsed].unique())[:20]
        print(f"Unparseable dates ({int(unparsed.sum())} docs): {bad_vals}"
              " -- add corrections to DATE_FIXES if these are OCR errors.")
    if out_of_range.any():
        bad_vals = sorted(date_chr.loc[out_of_range].unique())[:20]
        print(f"Out-of-range dates ({int(out_of_range.sum())} docs): {bad_vals}")

    df = df.loc[~(unparsed | out_of_range)].copy()
    df["week"] = df["date"].dt.to_period("W-SUN").dt.start_time  # Monday-start week
    return df


# ---------------------------------------------------------------------------
# 4. Dedup (3_editor&duplicates.R, stages D-F)
# ---------------------------------------------------------------------------
def dedupe(df: pd.DataFrame) -> pd.DataFrame:
    df = df.reset_index(drop=True)
    norm_title = (df["titles"].fillna("").str.lower()
                  .str.replace(r"[^\w\s]", "", regex=True)
                  .str.replace(r"\s+", " ", regex=True).str.strip())

    # ---- Stage 1: same normalized title, same paper family, <=2 days apart.
    # Only compares ADJACENT rows after sorting -- same approach (and same
    # limitation) as the R script's loop over ord.
    order = np.lexsort((df["date"].values, df["is_online"].values,
                         df["paper_family"].values, norm_title.values))
    dup1 = np.zeros(len(df), dtype=bool)
    nt, fam, date = norm_title.values[order], df["paper_family"].values[order], \
        df["date"].values[order]
    for i in range(1, len(order)):
        if (nt[i] and nt[i] == nt[i - 1] and fam[i] == fam[i - 1]
                and pd.notna(date[i]) and pd.notna(date[i - 1])
                and abs((date[i] - date[i - 1]) / np.timedelta64(1, "D")) <= 2):
            dup1[order[i]] = True
    print(f"Dedup stage 1 (same title/paper/<=2 days): dropping {dup1.sum()} docs.")
    df = df.loc[~dup1].reset_index(drop=True)

    # ---- Stage 2: TF-IDF cosine >= 0.85 within week blocks, same family only.
    from sklearn.feature_extraction.text import TfidfVectorizer
    from sklearn.metrics.pairwise import cosine_similarity

    week_num = ((df["date"] - df["date"].min()).dt.days // 7).values
    drop_ids: set[int] = set()
    seen_pairs: set[tuple[int, int]] = set()
    for w in sorted(set(week_num)):
        block = np.where((week_num == w) | (week_num == w + 1))[0]
        if len(block) < 2:
            continue
        tfidf = TfidfVectorizer(stop_words="english", max_features=20000).fit_transform(
            df["text"].values[block])
        sim = cosine_similarity(tfidf)
        iu = np.triu_indices_from(sim, k=1)
        for bi, bj, s in zip(iu[0], iu[1], sim[iu]):
            if s < 0.85:
                continue
            i, j = int(block[bi]), int(block[bj])
            pair = (min(i, j), max(i, j))
            if pair in seen_pairs:
                continue
            seen_pairs.add(pair)
            if df["paper_family"].iat[i] != df["paper_family"].iat[j]:
                continue  # cross-paper syndication: keep both
            if i in drop_ids or j in drop_ids:
                continue
            # Same tie-break rule as the R script: drop i if i is online,
            # otherwise drop j (even if j also happens to be online).
            drop_ids.add(i if df["is_online"].iat[i] else j)

    print(f"Dedup stage 2 (TF-IDF cosine >=0.85, same paper): "
          f"dropping {len(drop_ids)} docs.")
    return df.drop(index=list(drop_ids)).reset_index(drop=True)


def check_ontario_filter(df: pd.DataFrame) -> pd.DataFrame:
    text_lower = df["text"].str.lower()
    keep = text_lower.map(is_ontario_article)
    print(f"Ontario-vs-federal filter: keeping {int(keep.sum())} of {len(df)} "
          f"docs. Spot-check a few dropped titles before trusting this on "
          f"the full corpus:")
    print(df.loc[~keep, "titles"].head(10).to_string())
    return df.loc[keep].reset_index(drop=True)


# ---------------------------------------------------------------------------
# 4b. Hand-coded election-relevance flag (articles.csv `election_relevant`).
# Applied AFTER the Ontario-vs-federal signal filter -- that keeps anything
# with more Ontario than federal signal words, this narrows to articles a
# human marked as actually about the election. Mirrors the
# `election_relevant %in% "yes"` step in R_Scripts/5_key_atm_analysis.R.
# ---------------------------------------------------------------------------
def filter_election_relevant(df: pd.DataFrame) -> pd.DataFrame:
    if "election_relevant" not in df.columns:
        print("No `election_relevant` column -- skipping relevance filter.")
        return df
    rel = df["election_relevant"].astype(str).str.strip().str.lower()
    keep = rel.eq("yes")  # anything not exactly "yes" (incl. "no"/NaN) is dropped
    breakdown = rel.loc[~keep].value_counts(dropna=False).to_dict()
    print(f"election_relevant filter: keeping {int(keep.sum())} of {len(df)} "
          f"docs ({int((~keep).sum())} dropped; non-'yes' values: {breakdown}).")
    return df.loc[keep].reset_index(drop=True)


# ---------------------------------------------------------------------------
# 5. Embeddings (cached) + BERTopic
# ---------------------------------------------------------------------------
def embed(df: pd.DataFrame, embedding_model, model_name: str, cache: bool) -> np.ndarray:
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    doc_hash = hashlib.md5(
        (model_name + "|" + "|".join(df["ID"].astype(str))).encode()).hexdigest()[:16]
    cache_path = CACHE_DIR / f"embeddings_{doc_hash}.npy"
    if cache and cache_path.exists():
        print(f"Reusing cached embeddings: {cache_path.name}")
        return np.load(cache_path)

    print(f"Embedding {len(df)} documents with {model_name} "
          f"(this is the slow step) ...")
    embeddings = embedding_model.encode(df["text"].tolist(), show_progress_bar=True,
                                         batch_size=32)
    np.save(cache_path, embeddings)
    print(f"Cached embeddings to {cache_path.name}")
    return embeddings


def fit_bertopic(df: pd.DataFrame, embeddings: np.ndarray, embedding_model,
                  min_topic_size: int, nr_topics: int | None = None):
    from bertopic import BERTopic
    from sklearn.feature_extraction.text import CountVectorizer

    # ngram_range=(1, 2) so phrase-y keywords ("health care", "post
    # secondary") can surface as bigrams in topic representations --
    # the BERTopic analogue of compounding phrases before building the dfm
    # in 5_key_atm_analysis.R section 1.
    vectorizer_model = CountVectorizer(stop_words="english", ngram_range=(1, 2),
                                        min_df=5)
    topic_model = BERTopic(
        embedding_model=embedding_model,
        vectorizer_model=vectorizer_model,
        seed_topic_list=SEED_TOPIC_LIST,
        min_topic_size=min_topic_size,
        calculate_probabilities=False,
        verbose=True,
    )
    topics, _ = topic_model.fit_transform(df["text"].tolist(), embeddings)
    if nr_topics:
        topic_model.reduce_topics(df["text"].tolist(), nr_topics=nr_topics)
        topics = topic_model.topics_
    df = df.copy()
    df["topic"] = topics

    info = topic_model.get_topic_info()
    print("\n=== Fitted topics (id, size, top words) ===")
    print(info[["Topic", "Count", "Name"]].to_string(index=False))

    print("\n=== SUGGESTED (unverified) topic labels ===")
    print("Heuristic only -- overlap between each topic's top words and your")
    print("seed keyword lists. seed_topic_list nudges but does not force")
    print("topic formation, so confirm by eye before relying on this, then")
    print("set real labels with topic_model.set_topic_labels({...}).")
    for _, row in info.iterrows():
        if row["Topic"] == -1:
            continue
        top_words = {w for w, _ in topic_model.get_topic(row["Topic"])}
        best_label, best_overlap = None, 0
        for label, seeds in zip(SEED_LABELS, SEED_TOPIC_LIST):
            overlap = len(top_words & set(seeds))
            if overlap > best_overlap:
                best_label, best_overlap = label, overlap
        if best_label:
            print(f"  Topic {row['Topic']:>3} ({row['Count']} docs) "
                  f"-> maybe '{best_label}' (overlap={best_overlap}): {row['Name']}")

    return topic_model, df


# ---------------------------------------------------------------------------
# 6. Plots + outputs
# ---------------------------------------------------------------------------
# Topics kept out of every plot. -1 is BERTopic's outlier bucket; topic 0 is
# the largest catch-all cluster and is excluded on request. The CSV exports
# still contain every topic -- this only affects the visualizations.
VIZ_EXCLUDE_TOPICS = (-1, 0)


def _viz_topics(topic_model, top_n: int = 12) -> list[int]:
    """Topic ids to show in plots: most frequent, minus VIZ_EXCLUDE_TOPICS."""
    info = topic_model.get_topic_info()
    info = info[~info["Topic"].isin(VIZ_EXCLUDE_TOPICS)]
    return info.sort_values("Count", ascending=False)["Topic"].head(top_n).tolist()


def save_keyword_freq_plot(df: pd.DataFrame):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    text_lower = df["text"].str.lower()
    counts = {}
    for label, seeds in zip(SEED_LABELS, SEED_TOPIC_LIST):
        pat = re.compile(r"\b(" + "|".join(re.escape(s) for s in seeds) + r")\b")
        counts[label] = int(text_lower.map(lambda t: len(pat.findall(t))).sum())

    fig, ax = plt.subplots(figsize=(8, 5))
    items = sorted(counts.items(), key=lambda kv: kv[1])
    ax.barh([k for k, _ in items], [v for _, v in items])
    ax.set_xlabel("Keyword mentions across corpus")
    ax.set_title("Seed keyword frequency (~ keyATM visualize_keywords)")
    fig.tight_layout()
    PLOTS_DIR.mkdir(exist_ok=True)
    fig.savefig(PLOTS_DIR / "keyword_freq_bertopic.png", dpi=150)
    plt.close(fig)


def save_topic_frequency_plot(topic_model):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    info = topic_model.get_topic_info()
    info = info[~info["Topic"].isin(VIZ_EXCLUDE_TOPICS)].sort_values("Count").tail(12)
    fig, ax = plt.subplots(figsize=(8, 5))
    ax.barh(info["Name"], info["Count"])
    ax.set_xlabel("Documents")
    ax.set_title("Topic frequency (~ keyATM plot_topicprop)")
    fig.tight_layout()
    PLOTS_DIR.mkdir(exist_ok=True)
    fig.savefig(PLOTS_DIR / "Topic_frequency_bertopic.png", dpi=150)
    plt.close(fig)


def save_html_and_try_png(fig, html_path: Path, png_path: Path):
    fig.write_html(str(html_path))
    try:
        fig.write_image(str(png_path))
    except Exception as exc:  # kaleido not installed, etc.
        print(f"Skipped static PNG export for {png_path.name} ({exc}). "
              f"`pip install kaleido` to enable it; the interactive "
              f"{html_path.name} was saved regardless.")


def save_newspaper_breakdown(topic_model, df: pd.DataFrame):
    topics_per_class = topic_model.topics_per_class(
        df["text"].tolist(), classes=df["origin_clean"].tolist())
    fig = topic_model.visualize_topics_per_class(
        topics_per_class, topics=_viz_topics(topic_model))
    save_html_and_try_png(
        fig, PLOTS_DIR / "topic_by_newspaper_bertopic.html",
        PLOTS_DIR / "topic_by_newspaper_bertopic.png")
    topics_per_class.to_csv(DATA_DIR / "bertopic_topics_per_newspaper.csv",
                             index=False)


# Ontario 2025 general election: writ dropped / campaign began 29 Jan 2025
# (election day was 27 Feb 2025).
ELECTION_CALL_DATE = pd.Timestamp("2025-01-29")


def save_weekly_trend(topic_model, df: pd.DataFrame):
    n_weeks = df["week"].nunique()
    topics_over_time = topic_model.topics_over_time(
        df["text"].tolist(), timestamps=df["date"].tolist(),
        nr_bins=min(50, max(2, n_weeks)))

    # Show every topic BERTopic found -- the seeded keyword topics AND the
    # unseeded "other" topics -- not just the top 12 by size. Still drop the
    # outlier bucket (-1) and the catch-all topic 0.
    show_topics = [t for t in topic_model.get_topic_info()["Topic"]
                   if t not in VIZ_EXCLUDE_TOPICS]
    fig = topic_model.visualize_topics_over_time(
        topics_over_time, topics=show_topics)

    # Vertical marker at the start of the campaign period. add_vline's own
    # annotation_text arg chokes on a datetime x-axis in current plotly, so
    # the label is a separate paper-referenced annotation.
    fig.add_vline(x=ELECTION_CALL_DATE, line_width=2, line_dash="dash",
                  line_color="firebrick")
    fig.add_annotation(x=ELECTION_CALL_DATE, y=1.0, yref="paper",
                       text="Election called — 29 Jan 2025", showarrow=False,
                       xanchor="left", yanchor="bottom",
                       font=dict(color="firebrick"))

    save_html_and_try_png(
        fig, PLOTS_DIR / "timetrend_bertopic.html",
        PLOTS_DIR / "timetrend_bertopic.png")
    topics_over_time.to_csv(DATA_DIR / "bertopic_topics_over_time.csv",
                             index=False)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                      formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--input", type=Path, default=DATA_CSV,
                         help="Path to articles.csv (default: data/articles.csv)")
    parser.add_argument("--sample", type=int, default=None,
                         help="Randomly sample N articles after cleaning, "
                              "for a fast test run.")
    parser.add_argument("--seed", type=int, default=1998,
                         help="Random seed (matches the R script's keyATM seed).")
    parser.add_argument("--embedding-model", default="all-mpnet-base-v2",
                         help="sentence-transformers model name.")
    parser.add_argument("--min-topic-size", type=int, default=30,
                         help="BERTopic min_topic_size (smaller = more, "
                              "smaller topics).")
    parser.add_argument("--nr-topics", type=int, default=None,
                         help="Merge down to roughly this many topics after "
                              "fitting (BERTopic's reduce_topics), if you "
                              "want a fixed count closer to keyATM's "
                              "no_keyword_topics setup. Default: let "
                              "HDBSCAN decide.")
    parser.add_argument("--use-cache", action="store_true",
                         help="Reuse cached embeddings for this exact "
                              "document set if available.")
    parser.add_argument("--skip-dedup", action="store_true",
                         help="Skip the title/TF-IDF dedup pass (faster, "
                              "for quick iteration).")
    args = parser.parse_args()

    ARTICLES_DIR.mkdir(exist_ok=True)  # citation PDFs go here, not corpus data
    PLOTS_DIR.mkdir(exist_ok=True)
    DATA_DIR.mkdir(exist_ok=True)

    df = load_articles(args.input)
    df = drop_junk_and_letters(df)
    df = clean_origin_and_dates(df)
    if not args.skip_dedup:
        df = dedupe(df)
    df = check_ontario_filter(df)
    df = filter_election_relevant(df)

    print(f"\nFinal corpus after all cleaning: {len(df)} documents.")
    print(df["origin_clean"].value_counts().to_string())

    if args.sample:
        df = df.sample(n=min(args.sample, len(df)), random_state=args.seed)
        print(f"Sampled down to {len(df)} documents (--sample {args.sample}).")

    from sentence_transformers import SentenceTransformer
    embedding_model = SentenceTransformer(args.embedding_model)

    embeddings = embed(df, embedding_model, args.embedding_model, cache=args.use_cache)
    topic_model, df = fit_bertopic(df, embeddings, embedding_model,
                                    args.min_topic_size, args.nr_topics)

    save_keyword_freq_plot(df)
    save_topic_frequency_plot(topic_model)
    save_newspaper_breakdown(topic_model, df)
    save_weekly_trend(topic_model, df)

    topic_model.get_topic_info().to_csv(DATA_DIR / "bertopic_topics.csv", index=False)
    df[["ID", "titles", "origin_clean", "date", "topic"]].to_csv(
        DATA_DIR / "bertopic_document_topics.csv", index=False)
    topic_model.save(str(DATA_DIR / "bertopic_model"),
                      serialization="safetensors",
                      save_ctfidf=True,
                      save_embedding_model=args.embedding_model)

    print("\nDone. Plots in Plots/*_bertopic.*, tables in data/bertopic_*.csv, "
          "fitted model in data/bertopic_model/.")


if __name__ == "__main__":
    main()

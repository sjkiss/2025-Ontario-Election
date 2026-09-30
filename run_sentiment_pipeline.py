#!/usr/bin/env python3
"""
Batch sentiment/topic-extraction pipeline for the Ontario 2025 election corpus.

Two-pass design on the Anthropic Message Batches API — one async job per pass,
50% cheaper than live calls, no interactive rate limits:

  Pass 1 (Sonnet 5):  Chunks of CHUNK_SIZE articles per request (~1,100
                       requests for the full ~16.5k-article corpus). Applies
                       Step 1 (relevance filter) + Step 2 (topic/actor/
                       sentiment extraction) from
                       Claude_prompts/sentiment_analysis.md. Structured
                       outputs (JSON schema) instead of free-text CSV, so
                       parsing never depends on the model's formatting.

  Pass 2 (Opus 4.8):  A CERTAINTY_THRESHOLD-based spot-check. Every row with
                       any certainty field below the threshold is a
                       candidate; SPOTCHECK_FRACTION of those are randomly
                       sampled (seeded, reproducible) and sent to Opus for an
                       independent second opinion, batched CROSSCHECK_CHUNK
                       rows per request. Disagreements patch the row in
                       place; every verdict (agree or disagree) is logged.

Outputs (written to data/):
  sentiment_full.csv             - one row per actor/ascriber/topic dyad
  article_topic_summary_full.csv - one row per article, topics mentioned
  crosscheck_log.csv             - every Pass-2 verdict, for audit
  pass1_errors.csv               - any Pass-1 requests that errored/expired
  pass2_errors.csv               - any Pass-2 requests that errored/expired

Usage:
  pip install anthropic

  # Always test on a small sample first — verify the schema, the prompt
  # rendering, and a handful of real outputs before spending on the full run.
  python run_sentiment_pipeline.py --sample 50

  # The real thing. Confirms the estimated request/row count and asks before
  # submitting, since this is a real (if modest, ~$40-100) spend.
  python run_sentiment_pipeline.py --run-full

Requires ANTHROPIC_API_KEY in the environment (or `ant auth login`) — this is
separate, pay-per-token API billing, not a Claude Pro/Max subscription.
"""
import argparse
import csv
import json
import random
import sys
import time
from pathlib import Path

import anthropic
from anthropic.types.message_create_params import MessageCreateParamsNonStreaming
from anthropic.types.messages.batch_create_params import Request

ROOT = Path(__file__).resolve().parent
ARTICLES_CSV = ROOT / "data" / "articles.csv"
PROMPT_MD = ROOT / "Claude_prompts" / "sentiment_analysis.md"
OUT_DIR = ROOT / "data"

SONNET = "claude-sonnet-5"
OPUS = "claude-opus-4-8"
CHUNK_SIZE = 15            # articles per Pass-1 request
CROSSCHECK_CHUNK = 20      # flagged rows per Pass-2 request
CERTAINTY_THRESHOLD = 87
SPOTCHECK_FRACTION = 0.25
SEED = 42
POLL_SECONDS = 30
MAX_TOKENS_PASS1 = 8192
MAX_TOKENS_PASS2 = 4096

ORIGIN_NORMALIZE = {
    # Add entries here as you spot more variants in the corpus — the R
    # pipeline (4_dictionary.R) has a longer version of this same table.
    "the globe and mail": "Globe and Mail",
    "toronto star": "Toronto Star",
    "the toronto star": "Toronto Star",
    "the toronto sun": "Toronto Sun",
    "national post": "National Post",
    "the hamilton spectator": "Hamilton Spectator",
    "the ottawa citizen": "Ottawa Citizen",
    "the ottawa sun": "Ottawa Sun",
}


def normalize_origin(raw: str) -> str:
    base = raw.split(";")[0].strip()
    base = base.replace(" (Online)", "").replace(" (2011-)", "").strip()
    return ORIGIN_NORMALIZE.get(base.lower(), base)


# --------------------------------------------------------------------------
# Structured-output schemas
# --------------------------------------------------------------------------

ROW_SCHEMA = {
    "type": "object",
    "properties": {
        "topic": {"type": ["string", "null"]},
        "potential_merge": {"type": ["string", "null"]},
        "actor": {"type": "string"},
        "actor_party_bucket": {"type": ["string", "null"]},
        "sentiment_score": {"type": "number"},
        "ascribing": {"type": "string"},
        "public_reaction": {"type": ["string", "null"]},
        "other_actors": {"type": ["string", "null"]},
        "other_observations": {"type": ["string", "null"]},
        "example_quote": {"type": "string"},
        "quote_is_direct": {"type": "boolean"},
        "topic_certainty": {"type": ["integer", "null"]},
        "actor_certainty": {"type": "integer"},
        "sentiment_certainty": {"type": "integer"},
        "ascribing_certainty": {"type": "integer"},
        "public_certainty": {"type": ["integer", "null"]},
    },
    "required": [
        "topic", "potential_merge", "actor", "actor_party_bucket",
        "sentiment_score", "ascribing", "public_reaction", "other_actors",
        "other_observations", "example_quote", "quote_is_direct",
        "topic_certainty", "actor_certainty", "sentiment_certainty",
        "ascribing_certainty", "public_certainty",
    ],
    "additionalProperties": False,
}

PASS1_SCHEMA = {
    "type": "object",
    "properties": {
        "articles": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "article_id": {"type": "string"},
                    "relevant": {"type": "boolean"},
                    "skip_reason": {"type": ["string", "null"]},
                    "topics_mentioned": {"type": "array", "items": {"type": "string"}},
                    "rows": {"type": "array", "items": ROW_SCHEMA},
                },
                "required": [
                    "article_id", "relevant", "skip_reason",
                    "topics_mentioned", "rows",
                ],
                "additionalProperties": False,
            },
        },
    },
    "required": ["articles"],
    "additionalProperties": False,
}

REVIEW_SCHEMA = {
    "type": "object",
    "properties": {
        "reviews": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "row_id": {"type": "string"},
                    "agrees": {"type": "boolean"},
                    "reasoning": {"type": "string"},
                    "revised_sentiment_score": {"type": ["number", "null"]},
                    "revised_actor": {"type": ["string", "null"]},
                    "revised_ascribing": {"type": ["string", "null"]},
                    "revised_topic": {"type": ["string", "null"]},
                    "revised_certainty": {"type": ["integer", "null"]},
                },
                "required": [
                    "row_id", "agrees", "reasoning",
                    "revised_sentiment_score", "revised_actor",
                    "revised_ascribing", "revised_topic", "revised_certainty",
                ],
                "additionalProperties": False,
            },
        },
    },
    "required": ["reviews"],
    "additionalProperties": False,
}


# --------------------------------------------------------------------------
# Data loading
# --------------------------------------------------------------------------

def load_articles(sample: int | None) -> list[dict]:
    with open(ARTICLES_CSV, newline="", encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    usable = [
        r for r in rows
        if r["text"].strip() not in ("", "Not available.")
    ]
    print(f"Loaded {len(rows)} rows, {len(usable)} with usable text "
          f"({len(rows) - len(usable)} empty/unavailable, skipped for free).")
    if sample:
        random.seed(SEED)
        usable = random.sample(usable, min(sample, len(usable)))
        print(f"Sampled down to {len(usable)} articles (--sample {sample}).")
    return usable


def chunked(items: list, size: int):
    for i in range(0, len(items), size):
        yield items[i:i + size]


# --------------------------------------------------------------------------
# Pass 1: relevance filter + topic/sentiment extraction
# --------------------------------------------------------------------------

def load_instructions() -> str:
    return PROMPT_MD.read_text(encoding="utf-8")


def build_pass1_request(idx: int, articles: list[dict], instructions: str) -> Request:
    article_blocks = []
    for a in articles:
        article_blocks.append(
            f"=== ARTICLE {a['ID']} ===\n"
            f"Date: {a['dates']}\n"
            f"Section: {a['section']}\n"
            f"Origin: {normalize_origin(a['origin'])}\n"
            f"Title: {a['titles']}\n"
            f"Text:\n{a['text']}\n"
        )
    user_content = (
        "Apply Step 1 and Step 2 of the instructions to EACH of the "
        f"following {len(articles)} articles independently. For any article "
        "that fails Step 1 (not about the Ontario election or provincial "
        "issues thematically connected to it), set relevant=false and give "
        "skip_reason; leave rows empty. For relevant articles, extract one "
        "row per actor-ascriber dyad per the consolidation rule, and list "
        "every topic mentioned in the article (including ones with no "
        "dyad row) in topics_mentioned.\n\n"
        + "\n".join(article_blocks)
    )
    params: MessageCreateParamsNonStreaming = {
        "model": SONNET,
        "max_tokens": MAX_TOKENS_PASS1,
        "system": [
            {
                "type": "text",
                "text": instructions,
                "cache_control": {"type": "ephemeral"},
            },
        ],
        "output_config": {"format": {"type": "json_schema", "schema": PASS1_SCHEMA}},
        "messages": [{"role": "user", "content": user_content}],
    }
    return Request(custom_id=f"pass1-{idx}", params=params)


def run_batch(client: anthropic.Anthropic, requests: list[Request], label: str):
    print(f"Submitting {label}: {len(requests)} requests...")
    batch = client.messages.batches.create(requests=requests)
    print(f"  batch id: {batch.id}")
    while True:
        batch = client.messages.batches.retrieve(batch.id)
        counts = batch.request_counts
        print(f"  [{label}] status={batch.processing_status} "
              f"succeeded={counts.succeeded} errored={counts.errored} "
              f"processing={counts.processing}")
        if batch.processing_status == "ended":
            break
        time.sleep(POLL_SECONDS)
    return batch


def parse_pass1_results(client: anthropic.Anthropic, batch, articles_by_id: dict) -> tuple[list[dict], list[dict], list[dict]]:
    """Returns (master_rows, article_summaries, errors)."""
    master_rows, article_summaries, errors = [], [], []
    for result in client.messages.batches.results(batch.id):
        if result.result.type != "succeeded":
            errors.append({
                "custom_id": result.custom_id,
                "result_type": result.result.type,
                "error": getattr(result.result, "error", ""),
            })
            continue
        msg = result.result.message
        text = next((b.text for b in msg.content if b.type == "text"), None)
        if text is None:
            errors.append({"custom_id": result.custom_id, "result_type": "no_text_block", "error": ""})
            continue
        try:
            payload = json.loads(text)
        except json.JSONDecodeError as e:
            errors.append({"custom_id": result.custom_id, "result_type": "bad_json", "error": str(e)})
            continue
        for item in payload.get("articles", []):
            aid = item["article_id"]
            src = articles_by_id.get(aid)
            if src is None:
                errors.append({"custom_id": result.custom_id, "result_type": "unknown_article_id", "error": aid})
                continue
            article_summaries.append({
                "article_id": aid,
                "section": src["section"],
                "date": src["dates"],
                "origin": normalize_origin(src["origin"]),
                "relevant": item["relevant"],
                "skip_reason": item.get("skip_reason") or "",
                "topics_mentioned": "; ".join(item.get("topics_mentioned", [])),
            })
            if not item["relevant"]:
                continue
            for i, row in enumerate(item.get("rows", [])):
                row = dict(row)
                row["row_id"] = f"{aid}::{i}"
                row["article_id"] = aid
                row["section"] = src["section"]
                row["date"] = src["dates"]
                row["origin"] = normalize_origin(src["origin"])
                row["title"] = src["titles"]
                master_rows.append(row)
    return master_rows, article_summaries, errors


# --------------------------------------------------------------------------
# Pass 2: spot-check cross-verification
# --------------------------------------------------------------------------

CERT_FIELDS = ["topic_certainty", "actor_certainty", "sentiment_certainty",
               "ascribing_certainty", "public_certainty"]


def flagged_rows(master_rows: list[dict]) -> list[dict]:
    flagged = []
    for r in master_rows:
        for f in CERT_FIELDS:
            v = r.get(f)
            if v is not None and v < CERTAINTY_THRESHOLD:
                flagged.append(r)
                break
    return flagged


def build_pass2_request(idx: int, rows: list[dict]) -> Request:
    items = []
    for r in rows:
        items.append(
            f"row_id: {r['row_id']}\n"
            f"article_id: {r['article_id']}\n"
            f"topic: {r.get('topic')}\n"
            f"actor: {r['actor']}\n"
            f"sentiment_score: {r['sentiment_score']}\n"
            f"ascribing: {r['ascribing']}\n"
            f"example_quote: {r['example_quote']}\n"
            f"certainties: topic={r.get('topic_certainty')} actor={r['actor_certainty']} "
            f"sentiment={r['sentiment_certainty']} ascribing={r['ascribing_certainty']} "
            f"public={r.get('public_certainty')}\n"
        )
    user_content = (
        "You are cross-checking a first-pass classifier's low-certainty "
        "sentiment/topic/actor calls (each below 87% on at least one field). "
        "Form your own independent judgment from the quoted text — do not "
        "anchor on the first-pass value. For each row below, say whether you "
        "agree, and if not, give a revised value for whichever field(s) you "
        "disagree with (leave the rest null).\n\n" + "\n".join(items)
    )
    params: MessageCreateParamsNonStreaming = {
        "model": OPUS,
        "max_tokens": MAX_TOKENS_PASS2,
        "output_config": {"format": {"type": "json_schema", "schema": REVIEW_SCHEMA}},
        "messages": [{"role": "user", "content": user_content}],
    }
    return Request(custom_id=f"pass2-{idx}", params=params)


def parse_pass2_results(client: anthropic.Anthropic, batch) -> tuple[list[dict], list[dict]]:
    reviews, errors = [], []
    for result in client.messages.batches.results(batch.id):
        if result.result.type != "succeeded":
            errors.append({
                "custom_id": result.custom_id,
                "result_type": result.result.type,
                "error": getattr(result.result, "error", ""),
            })
            continue
        msg = result.result.message
        text = next((b.text for b in msg.content if b.type == "text"), None)
        if text is None:
            continue
        try:
            payload = json.loads(text)
        except json.JSONDecodeError:
            errors.append({"custom_id": result.custom_id, "result_type": "bad_json", "error": ""})
            continue
        reviews.extend(payload.get("reviews", []))
    return reviews, errors


def apply_reviews(master_rows: list[dict], reviews: list[dict]) -> list[dict]:
    by_id = {r["row_id"]: r for r in master_rows}
    log = []
    for rev in reviews:
        row = by_id.get(rev["row_id"])
        if row is None:
            continue
        log.append({
            "row_id": rev["row_id"], "article_id": row["article_id"],
            "agrees": rev["agrees"], "reasoning": rev["reasoning"],
            "before_sentiment": row["sentiment_score"], "before_actor": row["actor"],
            "before_ascribing": row["ascribing"], "before_topic": row.get("topic"),
        })
        if rev["agrees"]:
            continue
        if rev.get("revised_sentiment_score") is not None:
            row["sentiment_score"] = rev["revised_sentiment_score"]
        if rev.get("revised_actor"):
            row["actor"] = rev["revised_actor"]
        if rev.get("revised_ascribing"):
            row["ascribing"] = rev["revised_ascribing"]
        if rev.get("revised_topic") is not None:
            row["topic"] = rev["revised_topic"]
        if rev.get("revised_certainty") is not None:
            # Certainty was raised/lowered on cross-check but we don't know
            # which single field it targets from this schema — apply it to
            # sentiment_certainty, the field most often in question, and
            # note the ambiguity in the row's observations for a human pass.
            row["sentiment_certainty"] = rev["revised_certainty"]
            note = " [crosscheck revised sentiment_certainty]"
            row["other_observations"] = (row.get("other_observations") or "") + note
    return log


# --------------------------------------------------------------------------
# Output
# --------------------------------------------------------------------------

def write_csv(path: Path, rows: list[dict], fieldnames: list[str]):
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames, extrasaction="ignore")
        w.writeheader()
        for r in rows:
            w.writerow(r)
    print(f"Wrote {len(rows)} rows -> {path}")


def build_keyword_counts(master_rows: list[dict], article_summaries: list[dict]) -> list[dict]:
    from collections import Counter
    topic_counts = Counter()
    for r in master_rows:
        if r.get("topic"):
            for t in [s.strip() for s in r["topic"].split(";")]:
                topic_counts[t] += 1
    for a in article_summaries:
        if a["topics_mentioned"]:
            for t in [s.strip() for s in a["topics_mentioned"].split(";")]:
                topic_counts[t] += 1
    return [{"topic": t, "mention_count": c} for t, c in topic_counts.most_common()]


# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--sample", type=int, metavar="N", help="Run on a random sample of N articles (testing).")
    g.add_argument("--run-full", action="store_true", help="Run on the entire corpus. Costs real money — see the estimate printed before it submits.")
    ap.add_argument("--skip-crosscheck", action="store_true", help="Skip Pass 2 (useful for quick Pass-1-only test runs).")
    args = ap.parse_args()

    client = anthropic.Anthropic()  # picks up ANTHROPIC_API_KEY / `ant auth login` automatically
    instructions = load_instructions()
    articles = load_articles(args.sample)
    articles_by_id = {a["ID"]: a for a in articles}

    n_requests = (len(articles) + CHUNK_SIZE - 1) // CHUNK_SIZE
    print(f"\n{len(articles)} articles -> {n_requests} Pass-1 requests "
          f"(chunk size {CHUNK_SIZE}, model {SONNET}).")
    if args.run_full:
        confirm = input(
            f"This submits {n_requests} live Pass-1 requests against your API "
            f"key, plus a Pass-2 spot-check batch. Type 'yes' to proceed: "
        )
        if confirm.strip().lower() != "yes":
            print("Aborted.")
            sys.exit(0)

    # ---- Pass 1 ----
    pass1_requests = [
        build_pass1_request(i, chunk, instructions)
        for i, chunk in enumerate(chunked(articles, CHUNK_SIZE))
    ]
    batch1 = run_batch(client, pass1_requests, "Pass 1 (Sonnet 5)")
    master_rows, article_summaries, pass1_errors = parse_pass1_results(client, batch1, articles_by_id)
    print(f"Pass 1: {len(master_rows)} rows extracted from "
          f"{sum(1 for a in article_summaries if a['relevant'])} relevant articles "
          f"({len(pass1_errors)} request-level errors).")

    # ---- Pass 2 ----
    crosscheck_log = []
    if not args.skip_crosscheck:
        flagged = flagged_rows(master_rows)
        random.seed(SEED)
        sample_size = max(1, round(len(flagged) * SPOTCHECK_FRACTION)) if flagged else 0
        sampled = random.sample(flagged, sample_size) if flagged else []
        print(f"\n{len(flagged)} rows below {CERTAINTY_THRESHOLD}% certainty; "
              f"spot-checking {len(sampled)} ({SPOTCHECK_FRACTION:.0%} sample).")
        if sampled:
            pass2_requests = [
                build_pass2_request(i, chunk)
                for i, chunk in enumerate(chunked(sampled, CROSSCHECK_CHUNK))
            ]
            batch2 = run_batch(client, pass2_requests, "Pass 2 (Opus 4.8 cross-check)")
            reviews, pass2_errors = parse_pass2_results(client, batch2)
            crosscheck_log = apply_reviews(master_rows, reviews)
            agree_n = sum(1 for r in crosscheck_log if r["agrees"])
            print(f"Pass 2: {len(reviews)} verdicts ({agree_n} agree, "
                  f"{len(reviews) - agree_n} disagree/patched, "
                  f"{len(pass2_errors)} request-level errors).")
            write_csv(OUT_DIR / "pass2_errors.csv", pass2_errors,
                      ["custom_id", "result_type", "error"])

    # ---- Write outputs ----
    OUT_DIR.mkdir(exist_ok=True)
    row_fields = ["article_id", "section", "date", "origin", "title", "row_id",
                  "topic", "potential_merge", "actor", "actor_party_bucket",
                  "sentiment_score", "ascribing", "public_reaction", "other_actors",
                  "other_observations", "example_quote", "quote_is_direct",
                  "topic_certainty", "actor_certainty", "sentiment_certainty",
                  "ascribing_certainty", "public_certainty"]
    write_csv(OUT_DIR / "sentiment_full.csv", master_rows, row_fields)

    summary_fields = ["article_id", "section", "date", "origin", "relevant",
                       "skip_reason", "topics_mentioned"]
    write_csv(OUT_DIR / "article_topic_summary_full.csv", article_summaries, summary_fields)

    write_csv(OUT_DIR / "topic_keyword_counts_full.csv",
              build_keyword_counts(master_rows, article_summaries),
              ["topic", "mention_count"])

    if crosscheck_log:
        write_csv(OUT_DIR / "crosscheck_log.csv", crosscheck_log,
                  ["row_id", "article_id", "agrees", "reasoning",
                   "before_sentiment", "before_actor", "before_ascribing", "before_topic"])

    write_csv(OUT_DIR / "pass1_errors.csv", pass1_errors,
              ["custom_id", "result_type", "error"])

    print("\nDone.")


if __name__ == "__main__":
    main()

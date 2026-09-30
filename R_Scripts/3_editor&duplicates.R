# ==============================================================
# 01b (v4): junk pages + letters + SAME-PAPER-ONLY dedupe
# Changes from v3:
#   - removes ProQuest page-image junk docs ("January 8, 2024 (Page A8)")
#   - Stage 2 threshold raised 0.80 -> 0.85
#   - BOTH dedup stages now only drop a doc when its duplicate comes
#     from the SAME paper (print vs online edition). Syndicated copies
#     across different papers (Toronto Sun vs Ottawa Sun, Star vs
#     Spectator) are KEPT and counted, pending the team's decision.
# ==============================================================
library(quanteda)
library(quanteda.textstats)
library(magrittr)
library(here)
# 1. Rebuild df from the raw ProQuest files
source(here("R_Scripts/2_create_corpus.R"))
#Count documents
ndoc(df_corp)   # 16508
table(docvars(df_corp)$origin)
section_var <- "section"
source_var  <- "origin"
date_var    <- "dates"
title_var   <- "titles"
stopifnot(ndoc(df_corp) > 16000)

# ---- A. Remove ProQuest page-image junk docs ----------------------
is_page_junk <- grepl("^\\s*\\w+ \\d{1,2}, \\d{4} \\(Page ",
                      docvars(df_corp)[[title_var]])
is_page_junk[is.na(is_page_junk)] <- FALSE
table(is_page_junk)
df_corp <- corpus_subset(df_corp, !is_page_junk)

# ---- B. Letters to the editor (section + title) --------------------
sec_clean <- gsub("\\s", "", docvars(df_corp)[[section_var]])
letter_sec <- grepl("letter", sec_clean, ignore.case = TRUE)
letter_sec[is.na(letter_sec)] <- FALSE

ttl <- docvars(df_corp)[[title_var]]
letter_ttl <- grepl("^\\s*letter(s)?\\b.*(editor|:)|letters to the editor",
                    ttl, ignore.case = TRUE)
letter_ttl[is.na(letter_ttl)] <- FALSE

is_letter <- letter_sec | letter_ttl
table(is_letter)
df_corp <- corpus_subset(df_corp, !is_letter)
ndoc(df_corp)

# ---- C. Paper "family": same outlet regardless of edition ----------
# Maps print + online editions of a paper to one label. Different
# papers in the same CHAIN (Toronto Sun vs Ottawa Sun) stay distinct
# on purpose — cross-paper syndication is the team's call.
paper_id <- function(x) {
  x <- gsub("\\s", "", tolower(x))    # kill corrupted spaces FIRST
  dplyr::case_when(
    grepl("globeandmail",      x) ~ "globe",
    grepl("nationalpost",      x) ~ "natpost",
    grepl("torontostar",       x) ~ "star",
    grepl("spectator",         x) ~ "hamspec",
    grepl("torontosun",        x) ~ "torsun",
    grepl("ottawasun",         x) ~ "ottsun",
    grepl("ottawacitizen",     x) ~ "ottcitizen",
    grepl("saultstar",         x) ~ "saultstar",
    grepl("windsorstar",       x) ~ "windsorstar",
    grepl("londonfreepress",   x) ~ "lfp",
    grepl("sudburystar",       x) ~ "sudburystar",
    grepl("whig",              x) ~ "kingstonwhig",
    grepl("standard",          x) ~ "stcstandard",   # after whig, so Whig-Standard wins
    grepl("record",            x) ~ "record",
    TRUE ~ gsub("\\(online\\)|\\(2011-\\)|[[:punct:]]", "",
                sub(";.*$", "", x))
  )
}
dv <- docvars(df_corp)
dv$.date      <- as.Date(dv[[date_var]])
dv$.is_online <- grepl("online", dv[[source_var]], ignore.case = TRUE)
dv$.id    <- paper_id(dv[[source_var]])
sort(table(dv$.id), decreasing = TRUE)   # check the mapping

# ---- D. Stage 1: same title, <=2 days, SAME family ------------------
norm_title <- tolower(dv[[title_var]])
norm_title <- gsub("[[:punct:]]", "", norm_title)
norm_title <- gsub("\\s+", " ", trimws(norm_title))

ord <- order(norm_title, dv$.id, dv$.is_online, dv$.date)
dup_stage1 <- logical(ndoc(df_corp))
nt <- norm_title[ord]; dt <- dv$.date[ord]; fm <- dv$.id[ord]
for (i in 2:length(ord)) {
  same_title  <- !is.na(nt[i]) && !is.na(nt[i-1]) && nt[i] == nt[i-1]
  same_paper <- !is.na(fm[i]) && !is.na(fm[i-1]) && fm[i] == fm[i-1]
  close_date  <- !is.na(dt[i]) && !is.na(dt[i-1]) &&
    abs(as.numeric(dt[i] - dt[i-1])) <= 2
  if (isTRUE(same_title) && isTRUE(same_paper) && close_date)
    dup_stage1[ord[i]] <- TRUE
}
sum(dup_stage1)   # will be LOWER than v3's 1,637 — cross-paper kept now

df_corp <- df_corp[!dup_stage1]
dv      <- dv[!dup_stage1, ]

# ---- E. Stage 2: tf-idf cosine >= 0.85, SAME family only ------------
dedup_dfm <- df_corp %>%
  tokens(remove_punct = TRUE, remove_numbers = TRUE) %>%
  tokens_tolower() %>%
  tokens_remove(stopwords("en")) %>%
  dfm() %>%
  dfm_tfidf()

week_id <- as.numeric(dv$.date - min(dv$.date, na.rm = TRUE)) %/% 7
all_pairs <- list()
for (w in sort(unique(week_id[!is.na(week_id)]))) {
  in_block <- which(!is.na(week_id) & (week_id == w | week_id == w + 1))
  if (length(in_block) < 2) next
  sim <- textstat_simil(dedup_dfm[in_block, ], method = "cosine",
                        margin = "documents", min_simil = 0.85)
  p <- as.data.frame(sim)
  if (nrow(p) > 0) all_pairs[[length(all_pairs) + 1]] <- p
}
pairs <- unique(do.call(rbind, all_pairs))
nrow(pairs)

i1 <- match(as.character(pairs$document1), docnames(df_corp))
i2 <- match(as.character(pairs$document2), docnames(df_corp))
pairs$same_paper <- dv$.id[i1] == dv$.id[i2]

# How much cross-paper syndication are we keeping? (Simon)
table(pairs$same_paper)

pair_check <- data.frame(
  sim     = round(pairs$cosine, 3),
  fam     = pairs$same_paper,
  title1  = substr(dv[[title_var]][i1], 1, 55),
  title2  = substr(dv[[title_var]][i2], 1, 55),
  source1 = substr(dv[[source_var]][i1], 1, 28),
  source2 = substr(dv[[source_var]][i2], 1, 28)
)
# Inspect the risky end of the SAME-family pairs (the ones we'll drop):
subset(pair_check, fam) %>% {.[order(.$sim), ]} %>% head(25)
# And glance at what we're sparing:
subset(pair_check, !fam) %>% {.[order(.$sim), ]} %>% head(10)

# ---- F. Commit drops: same-family pairs only ------------------------
sf_pairs <- pairs[pairs$same_paper, ]
drop_ids <- character(0)
for (k in seq_len(nrow(sf_pairs))) {
  a <- as.character(sf_pairs$document1[k])
  b <- as.character(sf_pairs$document2[k])
  if (a %in% drop_ids || b %in% drop_ids) next
  a_online <- dv$.is_online[match(a, docnames(df_corp))]
  drop_ids <- c(drop_ids, if (isTRUE(a_online)) a else b)
}
length(drop_ids)

df_corp <- df_corp[!docnames(df_corp) %in% drop_ids]
ndoc(df_corp)
pair_check %>% view()
# Save the syndication evidence for the team discussion:
# write.csv(subset(pair_check, !fam), "syndicated_pairs_kept.csv", row.names = FALSE)

write.csv(df, "data/articles.csv")

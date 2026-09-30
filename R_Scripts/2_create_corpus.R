# Quanteda
library(quanteda)
library(quanteda.textstats)

library(quanteda)
library(magrittr)

# Source the read news scripts
library(here)
source(here("R_Scripts/1_read_in_news.R"))
#Create corpus
df_corp<-corpus(df, text_field="text")

# ---- Fix spacing artifact (missing space after periods) ----
df_corp <- gsub("([a-z])\\.([A-Z])", "\\1. \\2", df_corp)

df_tokens <- tokens(df_corp, remove_punct = TRUE) %>%
  tokens_remove(c(stopwords("en"), "said", "mr", "ms", "mrs",
                  "also", "get")) %>%
  tokens_tolower()

# ---- Ontario signal, minus bare "ford" (handled separately below) ----
on_signal_rest <- dictionary(list(
  on = c("crombie", "stiles", "schreiner",
         "ontario pc*", "ontario liberal*", "ontario ndp", "ontario green*",
         "ontario election", "ontario premier")
))

# ---- Context words that must co-occur with bare "ford" for it to count ----
context_signal <- dictionary(list(
  ctx = c("doug", "premier", "queen*s park", "ontario")
))

# ---- Federal signal ----
fed_signal <- dictionary(list(
  fed = c("carney", "trudeau", "poilievre", "freeland", "gould", "baylis",
          "dhalla", "jagmeet", "singh", "blanchet", "prime minister")
))

# Bare "ford" counts
ford_only <- dictionary(list(ford = "ford"))
ford_dfm <- df_tokens %>% tokens_lookup(ford_only) %>% dfm()
ford_count <- ford_dfm[, "ford"] %>% as.numeric()

# Context word counts (per document)
context_dfm <- df_tokens %>% tokens_lookup(context_signal) %>% dfm()
context_count <- context_dfm[, "ctx"] %>% as.numeric()

# "ford" only counts toward Ontario signal if a context word is present in the same doc
ford_valid <- ifelse(context_count > 0, ford_count, 0)

# Rest of Ontario signal (everything except bare "ford")
on_dfm_rest <- df_tokens %>% tokens_lookup(on_signal_rest) %>% dfm()
on_count_rest <- on_dfm_rest[, "on"] %>% as.numeric()

# Combined Ontario count = rest of dictionary + validated "ford" mentions
on_count_combined <- on_count_rest + ford_valid

# Federal count
fed_dfm <- df_tokens %>% tokens_lookup(fed_signal) %>% dfm()
fed_count <- fed_dfm[, "fed"] %>% as.numeric()

# Keep: Ontario signal (context-gated) > federal signal
keep_combined <- on_count_combined > fed_count
table(keep_combined)

df_tokens_on <- df_tokens[keep_combined]
df_corp_on   <- df_corp[keep_combined]
df_corp_fed  <- df_corp[!keep_combined]


# ---- 4. Verify the filter ----
ndoc(df_corp_on)
head(df_corp_on$titles, 25)      # check stragglers are gone

# ---- 5. Dictionaries ----
party_dict <- dictionary(list(
  liberals                  = c("liberals"),
  ontario_liberals          = c("ontario liberals", "ontario liberal"),
  conservatives             = c("conservative", "conservatives"),
  progressive_conservatives = c("progressive conservatives", "PCs", "progressive conservative"),
  ontario_conservatives     = c("ontario conservatives")
))

leader_dictionaries <- dictionary(list(
  ford      = c("doug ford", "ford"),
  crombie   = c("crombie"),
  stiles    = c("stiles"),
  schreiner = c("schreiner")
))

# ---- 6. Party counts (Ontario-only) ----
df_tokens_on %>%
  tokens_lookup(party_dict, nested_scope = "dictionary") %>%
  dfm() %>%
  colSums()

# ---- 7. Leader counts (Ontario-only) ----
df_tokens_on %>%
  tokens_lookup(leader_dictionaries) %>%
  dfm() %>%
  textstat_frequency()

# ---- 8. Optional: confirm "ford" mentions are Doug Ford ----
kwic(df_tokens_on, "ford", window = 8)




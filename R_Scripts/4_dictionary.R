# ==============================================================
# 03: Topic dictionary counts (issues of interest)
# Assumes df_tokens_on exists (Ontario-only tokens from the main
# filtering script). NOTE: because that pipeline removes stopwords
# BEFORE lookup, dictionary phrases must not contain stopwords
# (e.g. "cost of living" would never match — "of" is gone).
# ==============================================================
library(quanteda)
library(quanteda.textstats)
library(magrittr)
library(ggplot2)
library(keyATM)
source("R_Scripts/3_editor&duplicates.R")

# this rewrites df_tokens_on based on the deduped corpus
df_tokens_on <- df_tokens_on[docnames(df_tokens_on) %in% docnames(df_corp)]


## ---- 2. Covariates: clean origin ONCE, properly ----------------------------
## Canonical key = lowercase, letters only, leading "the" dropped. This absorbs
## OCR spaces inside words ("Natio nal Post", "The Hamilton Spec tator") that
## str_squish and hand-typed replace() rules can never keep up with.
CANON <- c(
  globeandmail         = "The Globe and Mail",
  ottawacitizen        = "The Ottawa Citizen",
  ottawasun            = "The Ottawa Sun",
  torontostar          = "Toronto Star",
  torontosun           = "The Toronto Sun",
  windsorstar          = "The Windsor Star",
  hamiltonspectator    = "The Hamilton Spectator",
  spectator            = "The Hamilton Spectator",   # Spectator == Hamilton Spectator
  nationalpost         = "National Post",
  saultstar            = "Sault Star",
  sudburystar          = "Sudbury Star",
  kingstonwhigstandard = "Kingston Whig-Standard",
  standard             = "The Standard"              # St. Catharines -- separate paper
)

docvars(df_tokens_on) <- docvars(df_tokens_on) %>%
  mutate(
    raw_origin = str_squish(str_extract(origin, "^[^;(]+")),
    key    = str_remove(str_to_lower(str_remove_all(raw_origin, "[^A-Za-z]")), "^the"),
    origin = unname(CANON[key]),
    origin = replace(origin, is.na(origin), "Other"),
    ## Set the reference level EXPLICITLY -- otherwise it's whichever level
    ## your locale happens to sort first, and by_strata_DocTopic breaks.
    origin = relevel(factor(origin), ref = "Other")
  )

#Check that the origin manipulation has worked
docvars(df_tokens_on) %>% 
  count(origin)


# ---- 1. Topic dictionary ------------------------------------------
topic_dict <- dictionary(list(
  housing = c("housing", "rent", "rents", "renter*", "landlord*",
              "tenant*", "mortgage*", "homeless*", "condo*",
              "housing affordability", "home prices", "homebuilding",
              "homebuilder*", "housing starts"),
  
  tariffs_trade = c("tariff*", "free trade", "trade war*",
                    "protectionis*", "interprovincial trade",
                    "trade deal*", "trade agreement*", "countervail*",
                    "buy canadian", "buy ontario"),
  
  taxes = c("tax", "taxes", "taxation", "taxpayer*", "carbon tax",
            "income tax", "property tax*", "hst", "tax cut*",
            "tax credit*", "tax break*"),
  
  health_care = c("health care", "healthcare", "hospital*",
                  "family doctor*", "family physician*", "primary care",
                  "emergency room*", "nurse*", "nursing", "physician*",
                  "wait times", "long-term care", "ohip", "surger*"),
  
  education = c("education", "school*", "teacher*", "classroom*",
                "curriculum", "kindergarten", "school board*",
                "class sizes"),
  
  post_secondary = c("post-secondary", "postsecondary", "universit*",
                     "college", "colleges", "tuition", "college strike",
                     "college faculty", "opseu", "campus*",
                     "international student*"),
  
  immigration = c("immigration", "immigrant*", "migrant*", "refugee*",
                  "asylum", "newcomer*", "deportation*", "visa*"),
  
  crime = c("crime", "crimes", "criminal*", "police", "policing",
            "theft*", "auto theft", "shooting*", "homicide*",
            "murder*", "gun violence", "bail", "carjacking*",
            "gang*", "violent crime")
))
# Caveats worth knowing:
#  - "international student*" sits in post_secondary but arguably
#    also immigration; move/duplicate as you see fit
#  - "school*" will catch "schooling"/"schools" but also
#    "schoolyard" etc. — fine at this level of analysis
#  - education vs post_secondary overlap on "college strike" coverage
#    is intentional (K-12 vs PSE are separate issue spaces)

# ---- 2. Overall counts (Ontario-only corpus) ----------------------
topic_dfm <- df_tokens_on %>%
  tokens_lookup(topic_dict) %>%
  dfm()


# Total mentions per topic across the corpus
sort(colSums(topic_dfm), decreasing = TRUE)

# Number of ARTICLES mentioning each topic at least once
# (often the more honest measure — one obsessive article can't
#  dominate the counts)
sort(colSums(topic_dfm > 0), decreasing = TRUE)

# ---- 3. Spot-check the matches ------------------------------------
# Always kwic a couple of patterns to make sure the dictionary is
# catching what you think it is:
kwic(df_tokens_on, phrase("free trade"), window = 6) %>% head(10)
kwic(df_tokens_on, "college", window = 6) %>% head(10)

# ---- 4. Topic mentions by week (scaffold for the trend graph) -----
docvars(df_tokens_on, "week") <-
  as.Date(cut(as.Date(docvars(df_tokens_on, "dates")), "week"))

topic_week <- df_tokens_on %>%
  tokens_lookup(topic_dict) %>%
  dfm() %>%
  dfm_group(groups = docvars(df_tokens_on, "week")) %>%
  convert(to = "data.frame")

topic_week
topic_long <- tidyr::pivot_longer(topic_week, -doc_id,
                                   names_to = "topic",
                                   values_to = "mentions")
 topic_long$week <- as.Date(topic_long$doc_id)

 ggplot(topic_long, aes(week, mentions, colour = topic)) +
  geom_line() +
  labs(title = "Issue mentions by week, Ontario 2025 election coverage",
       x = NULL, y = "Dictionary hits") +
   theme_minimal()
 
# The leader-mentions-by-week graph is the same recipe: swap
# topic_dict for leader_dictionaries.
 
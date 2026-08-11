
#### Key ATM analysis ####
source("R_Scripts/2_create_corpus.R")
library(tidyverse)
library(keyATM)
dfm <- df_tokens_on %>% 
  dfm() 


keyatm_dfm <- keyATM_read(texts = dfm) 


keywords <- list(
  housing = c("housing", "rent", "rents", "renter", "landlord",
              "tenant", "mortgage", "homeless", "condo", "NIMBY",
              "affordability", "homebuilding",
              "homebuilder", "apartment", "apartments",
              "encampment", "house", "permit", "zoning"),
  
  tariffs_trade = c("tariff", "tariffs", "trade",
                    "protectionist", "countervailing",
                    "buy", "strong"),
  
  taxes = c("tax", "taxes", "taxation", "taxpayer", "hst"),
  
  health_care = c("health-care", "healthcare", "hospital",
                  "doctor", "physician", "care",
                  "nurse", "nursing", "hospitals", "dr", 
                  "ohip", "surgery"),
  
  education = c("education", "school", "teacher", "classroom",
                "teachers",
                "curriculum", "kindergarten", "schools", "students"),
  
  post_secondary = c("post-secondary", "postsecondary", "university",
                     "college", "colleges", "tuition",  
                     "professor", "opseu", "campus", "universities",
                     "osap",
                     "student"),
  
  immigration = c("immigration", "immigrant", "migrant", "refugee",
                  "asylum", "newcomer", "deportation", "visa", "immigrants",
                  "newcomers"),
  
  crime = c("crime", "crimes", "criminal", "police", "policing",
            "theft", "shooting", "homicide",
            "murder", "violence", "bail", "carjacking",
            "gang", "violent", "prison")
)
key_viz <- visualize_keywords(docs = keyatm_dfm, keywords = keywords)

Vars <- docvars(df_tokens_on)

Vars <- Vars %>% 
  mutate(origin = str_extract(origin, "^[^;]+"),
         origin = str_extract(origin, "^[^(]+"),
         origin = replace(origin, origin == " The G lobe and Mail ", " The Globe and Mail"),
         origin = replace(origin, origin == " The Globe and Mail ", " The Globe and Mail"),
         origin = replace(origin, origin == " The Otta wa Sun", " The Ottawa Sun"),
         origin = replace(origin, origin == " The Ottaw a Citizen ", " The Ottawa Citizen"),
         origin = replace(origin, origin == " The Ottawa Citizen ", " The Ottawa Citizen"),
         origin = replace(origin, origin == " The Ottawa Ci tizen ", " The Ottawa Citizen"),
         origin = replace(origin, origin == "The Ottawa Citizen", " The Ottawa Citizen"),
         origin = replace(origin, origin == " The Tor onto Sun", " The Toronto Sun"),
         origin = replace(origin, origin == " The Toronto Star ", " Toronto Star"),
         origin = replace(origin, origin == " The Toronto Su n ", " The Toronto Sun"),
         origin = replace(origin, origin == " The Toronto Sun ", " The Toronto Sun"),
         origin = replace(origin, origin == " The Windsor Star ", " The Windsor Star"),
         origin = replace(origin, origin == " Toronto S tar", " Toronto Star"),
         origin = replace(origin, origin == " The Spectator", " The Hamilton Spectator "),
         origin = replace(origin, origin == " The Hamilton Specta tor ", " The Hamilton Spectator "),
         origin = replace(origin, origin == " The Hamilton Sp ectator ", " The Hamilton Spectator "),
         origin = replace(origin, origin == " National Post ", " National Post"),
         origin = replace(origin, origin == " The Sault Star ", " Sault Star"),
         origin = replace(origin, origin == " The Kingston Whig-Standard ", " Kingston Whig - Standard"),
         origin = replace(origin, is.na(origin), "Other"),
  )
table(Vars$origin, useNA = 'ifany')

Vars2 <- Vars %>% 
  select(origin)

newssource <- keyATM(
  docs = keyatm_dfm,
  no_keyword_topics = 7,
  keywords = keywords,
  model = "covariates",
  model_settings = list(
    covariates_data = Vars2,
    covariates_formula = ~ origin
  ),
  options = list(seed = 1998)
)

Topic_frequency <- plot_topicprop(newssource, show_topic = 1:15)
newsource_keyatm <- top_words(newssource, n = 100)
ggsave("Plots/Topic_frequency.png", Topic_frequency, width = 8, height = 5)
covariates_info(newssource)



NEWSPAPERS <- c("National Post", "Sault Star", "The Globe and Mail",
                "The Hamilton Spectator ", "The Ottawa Citizen", "The Spectator",
                "The Sudbury Star ", "The Toronto Sun", "The Windsor Star", "Toronto Star")
Newspaper_df <- data.frame()
for(i in 1:length(NEWSPAPERS)){
  
  temp <- by_strata_DocTopic(newssource,
                             by_var = paste0("origin ", NEWSPAPERS[i]),
                             labels = c("other-paper", NEWSPAPERS[i]))
  
  
  df <- summary(temp)[[NEWSPAPERS[i]]]
  
  Newspaper_df <- bind_rows(Newspaper_df, df)
    
}

new_data <- covariates_get(newssource)

new_data[, paste0("origin ", NEWSPAPERS)] <- 0

pred <- predict(newssource, new_data, label = "Others")

Newspaper_df <- bind_rows(Newspaper_df, pred)

topic_by_newspaper <- Newspaper_df %>% 
  mutate(Topic = recode_values(Topic, 
                               "1_housing" ~ "Housing*",
                               "2_tariffs_trade" ~ "Tariffs/Trade*",
                               "3_taxes" ~ "Taxes*",
                               "4_health_care" ~ "Health Care*",
                               "5_education" ~ "Education*",
                               "6_post_secondary" ~ "Post-Secondary*",
                              # "7_immigration" ~ "LCBO",
                               "7_crime" ~ "Crime*",
                               "Other_1" ~ "Leaders",
                               "Other_2" ~ "Misc",
                               "Other_3" ~ "Scandals",
                               "Other_4" ~ "Transportation",
                               "Other_5" ~ "Ontario Place"),
         Topic = factor(Topic, levels = rev(c( "Housing*",
                                            "Tariffs/Trade*",
                                           "Taxes*",
                                           "Health Care*",
                                           "Education*",
                                           "Post-Secondary*",
                                           "Crime*",
                                           "Transportation",
                                           "Ontario Place",
                                           "Scandals",
                                           "Misc",
                                           "Leaders"))),
         label = factor(label, levels = c("National Post", "The Globe and Mail", "Toronto Star", "The Toronto Sun", "The Ottawa Citizen",
                                          "Sault Star", "The Hamilton Spectator ", "The Spectator",
                                          "The Sudbury Star ", "The Windsor Star",
                                          "Others"))) %>% 
  ggplot(aes(x = Point, xmin = Lower, xmax = Upper, y = Topic)) + 
  geom_point() + 
  geom_linerange() + 
  facet_wrap(~label) + 
  labs(x = expression(paste("Mean of ", theta))) + 
  theme_bw()

ggsave("Plots/topic_by_newspaper.png", topic_by_newspaper, width = 8, height = 8)

#### Overtime analysis ####

# Build the mask ONCE, based on Vars (which is aligned with df_tokens_on)
keep_weeks <- !is.na(Vars$week)

# Apply it to both objects
Vars_clean       <- Vars[keep_weeks, ]
df_tokens_on_clean <- df_tokens_on[keep_weeks]

# Clean malformed week values and convert to Date
Vars_clean <- Vars_clean %>%
  mutate(week = replace(week, week == "0002-06-03", "2024-06-03"),
         week = replace(week, week == "0020-02-24", "2025-02-24"),
         week = replace(week, week == "0020-05-11", "2024-05-11"),
         week = replace(week, week == "0202-01-04", "2024-01-04"),
         week = as.Date(week))

# keyATM's dynamic model checks that time_index changes by 0 or 1 between
# CONSECUTIVE documents (not just that the set of week numbers is gapless),
# so the documents must be sorted chronologically before building week_num
doc_order <- order(Vars_clean$week)

Vars_clean         <- Vars_clean[doc_order, ]
df_tokens_on_clean <- df_tokens_on_clean[doc_order]

# Now rebuild the dfm and keyatm_dfm from the reordered, filtered tokens
dfm <- df_tokens_on_clean %>%
  dfm()
keyatm_dfm_clean <- keyATM_read(texts = dfm)

Vars3 <- Vars_clean %>%
  mutate(week_num = dense_rank(week)) %>%
  select(week_num)

length(Vars3$week_num) == ndoc(dfm)  # should be TRUE
min(Vars3$week_num) == 1    # should be TRUE
all(diff(Vars3$week_num) %in% c(0, 1))  # should be TRUE -- this is what keyATM actually requires

overtime <- keyATM(
  docs = keyatm_dfm_clean,
  no_keyword_topics = 5,
  keywords = keywords,
  model = "dynamic",
  model_settings = list(
    time_index = Vars3$week_num,
    num_states = 10
  ),
  options = list(seed = 1998)
)

fig_timetrend <- plot_timetrend(overtime, time_index_label = Vars_clean$week, xlab = "Week")
fig_timetrend

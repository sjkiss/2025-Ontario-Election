##### Public Opinion Data #####

pacman::p_load(ggpattern,
               tidyverse,
               srvyr)

CES <- haven::read_dta("data/2025 Canadian Election Study v1.dta")

CES <- CES %>% 
  filter(cps25_province == 9)

CES <- CES %>% 
  mutate(Provincial_Vote = recode_values(pes25_provvote,
                                         1 ~ "Liberal",
                                         2 ~ "NDP",
                                         3 ~ "Green",
                                         11 ~ "Progressive Conservative"),
         Big_issue = recode_values(cps25_big_issue, 
                                   1 ~ "Climate and the Enivromnment",
                                   2 ~ "Climate and the Enivromnment",
                                   3 ~ "Another Issue",
                                   4 ~ "Housing Costs",
                                   5 ~ "Another Issue"),
         Big_issue = replace(Big_issue, str_detect(tolower(cps25_big_issue_5_TEXT), 
                                                   "trump|trade|tarifs|usa|tariff|aggression|relation|states|threat|sovereign|america"),
                             "Trump/Trade War"),
         Big_issue = replace(Big_issue, str_detect(tolower(cps25_big_issue_5_TEXT), "crime|safety|criminal|order"), "Crime"),
         Big_issue = replace(Big_issue, str_detect(tolower(cps25_big_issue_5_TEXT), "living|economy|recession"), "Cost of Living"),
         
         )

CES$cps25_big_issue_5_TEXT

Sample_percentages <- CES %>% 
  filter(!is.na(pes25_weight_general_all)) %>% 
  as_survey(weights = pes25_weight_general_all) %>% 
  group_by(Provincial_Vote) %>% 
  survey_tally() %>% 
  filter(!is.na(Provincial_Vote)) %>% 
  ungroup() %>% 
  mutate(prop = n/sum(n),
         Provincial_Vote = factor(Provincial_Vote, levels = rev(c("Progressive Conservative",
                                                              "Liberal",
                                                              "NDP",
                                                              "Green")))) %>% 
  ggplot(aes(x = prop, y = Provincial_Vote)) + 
  geom_col() +
  geom_text(aes(label = scales::percent(prop, accuracy = 0.1)),
            hjust = -0.1) +
  labs(y = "Provincial Vote Choice",
       x = "Percentage") +
  scale_x_continuous(labels = scales::percent,
                     expand = expansion(mult = c(0, 0.1))) +
  theme_bw()


ggsave("plots/Sample_percentages.png", Sample_percentages, width = 8, height = 4)
#### Demographic Correlates ####

CES <- CES %>% 
  mutate(Age = cps25_age_in_years,
         Gender = recode_values(cps25_genderid,
                                1 ~ "Man",
                                2 ~ "Woman",
                                3 ~ "Non-binary"),
         Degree = ifelse(cps25_education %in% c(7, 9, 10, 11), 1, 0),
         Employed = ifelse(cps25_employment %in% c(1, 2, 3, 9, 11), 1, 0),
         Renter = ifelse(cps25_rent == 1, 1, 0)
         )

CES_srvy <- CES %>% 
  filter(!is.na(pes25_weight_general_all)) %>% 
as_survey(weights = pes25_weight_general_all)


Demographics <- CES_srvy %>% 
  group_by(Provincial_Vote) %>% 
  summarise(
            Percent_degree = survey_mean(Degree, vartype = "ci", level = 0.95),
            Percent_employed = survey_mean(Employed, vartype = "ci", level = 0.95),
            Percent_renters = survey_mean(Renter, na.rm = TRUE, vartype = "ci", level = 0.95)) %>% 
  pivot_longer(cols = starts_with("Percent")) %>% 
  mutate(
    stat = case_when(
      str_ends(name, "_low") ~ "lower",
      str_ends(name, "_upp") ~ "upper",
      TRUE                   ~ "percent"
    ),
    variable = str_remove(name, "_(low|upp)$")
  ) %>% 
  select(-name) %>% 
  pivot_wider(names_from = stat, values_from = value) %>% 
  filter(!is.na(Provincial_Vote)) %>% 
  mutate(variable = recode_values(variable, 
                                  "Percent_degree" ~ "% of Supporters with a Degree",
                                  "Percent_employed" ~ "% of Supporters Employed",
                                  "Percent_renters" ~ "% of Supporters who are Renters"),
         Provincial_Vote = factor(Provincial_Vote, levels = rev(c("Progressive Conservative",
                                                                  "Liberal",
                                                                  "NDP",
                                                                  "Green")))) %>% 
  ggplot(aes(x = percent, xmin = lower, xmax = upper, y = Provincial_Vote)) + 
  geom_point() + 
  geom_linerange() + 
  facet_wrap(~variable, ncol = 1) + 
  theme_bw() + 
  scale_x_continuous(labels = scales::percent) + 
  labs(x = "Percentage",
       y = "Provincial Vote Choice") 

#### Biggest Issue Canada will face ####

big_issue_levels <- rev(c("Climate and the Enivromnment",
                       "Housing Costs",
                       "Cost of Living",
                       "Trump/Trade War",
                       "Crime",
                       "Another Issue"))

CES %>%
  group_by(Provincial_Vote) %>%
  count(Big_issue) %>%
  filter(!is.na(Provincial_Vote) & !is.na(Big_issue)) %>%
  mutate(prop = n/sum(n)) %>%
  bind_rows(CES %>% 
              count(Big_issue) %>%
              filter( !is.na(Big_issue)) %>%
              mutate(prop = n/sum(n),
            Provincial_Vote = "Pooled")) %>% 
  mutate(Provincial_Vote = factor(Provincial_Vote, levels = rev(c("Pooled",
                                                                   "Progressive Conservative",
                                                                   "Liberal",
                                                                   "NDP",
                                                                   "Green"))),
         Big_issue = factor(Big_issue, levels = big_issue_levels)) %>% 
  ggplot(aes(x = prop, y = Provincial_Vote, group = Big_issue,
             pattern = Big_issue, pattern_angle = Big_issue)) +
  geom_col_pattern(position = position_dodge(width = 0.9),
                    colour = "black",
                    fill = "white",
                    pattern_fill = "black",
                    pattern_colour = "black",
                    pattern_density = 0.25,
                    pattern_spacing = 0.04) +
  geom_text(aes(label = scales::percent(prop, accuracy = 0.1)),
            hjust = -0.1,
            position = position_dodge(width = 0.9)) +
  labs(y = "Provincial Vote Choice",
       x = "Percentage",
       pattern = "Greatest Issue",
       pattern_angle = "Greatest Issue") +
  scale_x_continuous(labels = scales::percent,
                     expand = expansion(mult = c(0, 0.1))) +
  theme_bw() +
  scale_pattern_manual(values = c("stripe", "stripe", "crosshatch",
                                   "circle", "crosshatch", "none")) +
  scale_pattern_angle_manual(values = c(45, 135, 45, 0, 0, 0)) +
  guides(pattern = guide_legend(nrow = 2, byrow = TRUE, reverse = TRUE,
                                override.aes = list(fill = "white",
                                                    colour = "black")),
         pattern_angle = guide_legend(nrow = 2, byrow = TRUE, reverse = TRUE,
                                      override.aes = list(fill = "white",
                                                          colour = "black"))) +
  theme(legend.position = "bottom",
        legend.key.width = unit(1.6, "cm"),
        legend.key.height = unit(0.45, "cm"))

ggsave("plots/greatest_issue.png", width = 9, height = 6)

#### Responsibility for the Issue ####

CES %>% 
  group_by(Big_issue) %>% 
  count(cps25_big_issue_gov) %>% 
  mutate(prop = n/sum(n))



CES <- CES %>% 
  mutate(pes25_immigincrease = replace(pes25_immigincrease, pes25_immigincrease == 6, NA))

housing_exp <- estimatr::lm_robust(pes25_immigincrease ~ immigincrease_exp * Provincial_Vote,
                       data = CES)


housing_exp_df <- housing_exp %>% 
  marginaleffects::avg_predictions(variables = c("immigincrease_exp", "Provincial_Vote"))


housing_exp_plot <- housing_exp_df %>% 
  as.data.frame() %>% 
  mutate(Provincial_Vote = factor(Provincial_Vote,
                                  levels = rev(c("Progressive Conservative",
                                                                  "Liberal",
                                                                  "NDP",
                                                                  "Green"))),
         immigincrease_exp = recode_values(immigincrease_exp,
                                          "home_values" ~ "Increase Home Values",
                                          "housing_costs" ~ "Increase Housing Costs",
                                          "worsen_housing_crisis" ~ "Worsen the Housing Crisis")) %>% 
  ggplot(aes(x = estimate, y = Provincial_Vote, col = immigincrease_exp, xmin = conf.low, xmax = conf.high)) + 
  geom_point(position = position_dodge(width = 0.6)) + 
  geom_linerange(position = position_dodge(width = 0.6)) +
  theme_bw() + 
  labs(x = "Predicted Level of Agreement with Each Statement",
       y = "Provincial Vote Choice",
       col = "\"Immigrants ...\"") +
  scale_colour_manual(values = rev(c("black", "grey40", "grey70"))) + 
  guides(colour = guide_legend(reverse = TRUE,
                             nrow = 3)
         ) + 
  theme(legend.position = "bottom",
        legend.key.spacing.y = unit(-0.2, "cm") 
  )


ggsave("plots/housing_exp_plot.png", housing_exp_plot, width = 8, height = 5)



Step 1: Note if the article about the Ontario election. 
If the focus of the article is not about the Ontario election or provincial issues thematically connected to the 2025 election cycle (issues of provincial jurisdiction) the time the article was published doesn't matter only the relevence (e.g. an article about an event from the 1990s is not relevent) note that and skip this article. 

Step 2:
You are a document analyzer. Only use the articles and no outside sources. 

 Take into account the following topics: 

 housing
 tariffs_trade
 taxes
 health_care
 education (schools, school boards, etc.)
post_secondary (as it related to funding, student numbers, osap, international students)
immigration
crime
municipal powers
public transit (add an additional note for bike lanes)
 
If you feel that the article mentioned a topic not already identified mention the new topic. These are topics we think are important but there could be other topics. 

If you are unsure whether an actor mention fits into a specific category look it is better to create a new topic (just note what other category it is similar to in a column called potential_merge)

For each article examine:

Who is mentioned? 
Is the actor portrayed in a positive or negative light? 
- Give a relative sentiment score here (-1 most negative 1 most positive)
Who is ascribing the sentiment? 
e.g. the article author? the public? the opposition? (which parties?)
How is the public reacting to a political issue?
- Is there stated public reaction to an election issue (is it hurting a party in the polls, are there quotes from voters?)
- If the public is not mentioned do not mention it.
Is a specific topic from the topic list mentioned in relation to this actor?
- If it is more broadly about an actor you do not need to mention a topic. 
What other observations do you have about each article?

Do not combine parties/leaders if they ascirbe the same sentiment but you can combine other actors. (See the Appendix for a list of party leaders)

EXAMPLES:

 ARCHITECTURE Doug Ford did not solve the housing crisis.The Ontario Progressive Conservative Leader made big promises during his past term as premier. He said he would massively increase the housing supply, simplify the planning system and even deliver thousands of bargain-priced starter homes for young families.None of those things came to pass. This week, as Ontarians choose a new government, what can we learn from Mr. Ford‚Äôs shotgun promises and the absence of meaningful results?

Topic: Housing
 Actor: Ford
 Sentiment: Negative
 Ascribing: author
 Public: no mention


THis article talks about education and trade/tariffs as it relates Ford in a negative way (since there are two different topics create a seperate entry for each):

 Toronto-based writer Anyone following the current Ontario election could be forgiven for forgetting that education is a provincial responsibility. Progressive Conservative Leader Doug Ford has capitalized on the major distraction south of the border not only to justify a completely unjustifiable election, but also to focus Ontarians‚Äô attention away from more mundane matters of provincial jurisdiction.

Topic: Education/tariffs_trade
Actor: Ford
Sentiment: Negative
Ascribing: Author
Public: No mention


 Ontario Premier Doug Ford‚Äôs accelerated deal to expand alcohol sales to corner stores and other retailers will cost provincial taxpayers $1.4-billion over the next six years, the legislature‚Äôs financial watchdog says, much more than first disclosed.The price tag calculated by the province‚Äôs independent Financial Accountability Office (FAO), in a report released Monday on the eve of Mr. Ford‚Äôs impending snap election call, is well above the $225-million in potential payments to the private-sector Beer Store chain the government revealed when it announced its alcohol liberalization plan last May.That money was meant to ensure that a minimum number of Beer Store locations, which take empties back for the province‚Äôs deposit system for alcohol containers, stayed open until the end of this year.The government had acknowledged that there would be other costs under its new arrangement with the Beer Store, including millions in rebated fees, but had not provided comprehensive cost estimates.The alcohol deal, which allowed beer in corner stores 16 months earlier than previously possible, fulfilled a stalled Progressive Conservative election promise from 2018. But opposition critics have charged that the sped-up agreement was just a taxpayer-funded stagesetter for an early election call. Mr. Ford is to trigger the move on Tuesday, with Ontarians going to the polls Feb. 27.The government could have allowed beer in corner stores merely by waiting for the 10-year deal signed with the Beer Store in 2015 to lapse at the end of this year ‚Äì in time for what would have been the next regularly scheduled election in June, 2026.On Monday, the FAO said that of its $1.4-billion cost estimate, $612-million is directly attributable to payments and lost revenue until Jan. 1, 2026, when the original Beer Store deal would have expired. Another $817-million of the total relates to the costs to taxpayers from then until 2030, when the new transition agreement signed last year runs out.In all, government support for both the wine industry and the Beer Store will run to $489million, the agency says, a total that includes that initial $225-million for the beer retailer, which is controlled by multinational brewing giants.The reduction in provincial tax revenue comes to $1.28-billion, as sales shift to the new outlets, where purchasers are not charged the same alcohol taxes.But the FAO also says some of the losses will be offset by $353-million in increased net income over the next seven years from the Liquor Control Board of Ontario, which is serving as the monopoly wholesaler for the corner stores and other new outlets. This increase comes despite a 10-per-cent wholesale price discount granted to the new outlets.The FAO also said that its estimates depend on whether the current downward trend in alcohol sales continues and how fast booze sales migrate to the new outlets, meaning the total cost of the deal could range from $529million to $1.9-billion.The government defended its accelerated alcohol deal. Colin Blachar, a spokesperson for Finance Minister Peter Bethlenfalvy, whose portfolio includes the province‚Äôs alcohol sales regime, issued a statement saying that much of the price tag identified by the FAO comes from deliberate policy decisions to lower taxes and fees on booze and save consumers money.‚ÄúWe were elected twice on a promise to deliver people with more choice and convenience, and to end one of the worst deals in the province‚Äôs history that shut out local businesses in favour of large foreign corporations,‚Äù he said.Beer, wine and cider and premixed drinks have been available in participating convenience stores, big-box stores and an increased number of supermarkets since last fall.Liberal Leader Bonnie Crombie, whose party had previously estimated the true cost of the deal was $1-billion, cited the higher end of the FAO‚Äôs estimates, at $1.9-billion, on Monday, and said the cash should have gone to the ailing health care system.‚ÄúDoug Ford gave $1.9-billlion of your hardearned money to big beer companies and his American billionaire buddies who own 7-11 and Costco,‚Äù Ms. Crombie told reporters at Queen‚Äôs Park.NDP Leader Marit Stiles told reporters in Brampton that the alcohol deal shows Mr. Ford is a bad negotiator.‚ÄúDoug Ford is costing Ontarians billions of dollars,‚Äù she said. ‚ÄúWe can‚Äôt afford it any more.

Topic: Alcohol
Actor: Ford
Sentiment: Negative (but more neutral/objective)
Ascribing: Opposition (Crombie and Stiles)
Public: No mention

Step 3: 

Create a csv file with each variable you identify and the text of the article.
Each mentioned acscribing actor-sentiment conbination should be a row:
Do not combine parties/leaders as both the acrisber or the main actor the same sentiment but you can combine other actors. (See the APPENDIX for a list of party leaders)
Each row should be an actor-ascriber dyad (Multiple topics can be listed in the same row. Consolidate topics into one row only if their sentiment scores would land within ~0.3 of each other; otherwise split).
Also include the following meta data:
A certainty score for variable (e.g. topic, actor, sentiment, ascribing, public). 
the article ID. 
the section. 
the date.
the origin (shortened to just the publication name (merge online and non online versions))
exmaples that you use to acsribe sentiment. 
A boolen to indicate if the sentiment is from a direct quote or paraphrase.

Step 3: Spot check any variables (25%) that are are below 87% certainity use Opus 4.8 (as a sub agent) to cross check if the two models do not agree discuss the differences and come to an agreement. Note the disagreement and how you resolved it. 

Step 4:

Next, using the topics mentioned in step 1 and any new topics you identify act as a topic analyzer and create a seperate csv file with 1 row per article.

This csv file should include:
the article ID. 
the section. 
the date.
any topics mentioned in that article.

Also create a seperate csv file with the topics and keywords and counts related to those topic. 


APPENIDX:

Leaders and Parties:

Liberal (ontario liberal*): "crombie", "liberal member", "liberal backbencher", "liberal spokesperson"
NDP (ontario ndp): "stiles", "ndp member", "ndp backbecher", "ndp spokesperson"
Green (ontario green*): "schreiner", "green member", "green backbecher", "green spokesperson"
Pogressive Conservative (PC; progressive conserative*, ontario conserative): premier, Ford, the government, government minister, governmnet spokesperson

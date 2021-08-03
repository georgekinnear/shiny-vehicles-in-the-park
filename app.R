library(tidyverse)
library(shiny)
library(shinyjs)
library(pool)
library(yaml)

# Connection info is stored in dbconfig.yml (not in public repo) for security
dbconfig <- yaml::read_yaml("dbconfig.yml")
pool <- dbPool(
  drv = RMySQL::MySQL(),
  dbname = dbconfig$dbname,
  host = dbconfig$host,
  username = dbconfig$username,
  password = dbconfig$password
)
onStop(function() {
  poolClose(pool)
})

#
# Define the various judging groups
#
studies <- pool %>% 
  tbl("studies") %>% 
  collect()
# tibble::tribble(
#   ~study,                                                                        ~judging_prompt, ~judging_method, ~target_judges, ~judgements_per_judge,
#   "vehicle_pairs",                                      "Which is the most typical example of a vehicle?",        "binary",            20L,                  100L,
#   "vehicle_slider",                                      "Which is the most typical example of a vehicle?",        "slider",            20L,                  100L,
#   "violation_pairs", "A sign says No Vehicles in the Park. Which example would be the the worst violation?",        "binary",            20L,                  100L,
#   "violation_slider", "A sign says No Vehicles in the Park. Which example would be the the worst violation?",        "slider",            20L,                  100L,
#   "nuisance_pairs",                   "Which of the two examples would be the biggest nuisance in a park?",        "binary",            20L,                  100L,
#   "nuisance_slider",                   "Which of the two examples would be the biggest nuisance in a park?",        "slider",            20L,                  100L
# )

#
# Check on judging progress
#
all_existing_judgements <- pool %>% 
  tbl("judgements") %>% 
  select(-contains("comment")) %>% 
  collect() %>% 
  semi_join(studies, by = "study")

study_progress <- all_existing_judgements %>% 
  group_by(study, judge_id) %>% 
  tally() %>% 
  left_join(studies, by = "study") %>% 
  group_by(study) %>% 
  summarise(
    num_judges = n_distinct(judge_id),
    num_judgements = sum(n)
  )

study_status <- studies %>% 
  left_join(study_progress, by = "study") %>% 
  mutate(across(starts_with("num_"), ~replace_na(.x, 0)))

assign_to_study <- function() {
  # allocate to one of the study conditions, weighted by current progress
  study_status %>%
    # identify the number of judges needed by each condition to meet its target
    mutate(judge_slots = target_judges - num_judges) %>%
    # pick the condition with the most open slots
    slice_max(judge_slots, n = 1, with_ties = FALSE) %>% 
    #pull(study_id)
    unlist()
}

#Check that the assignment is working the way it should
# simulate_assignment <- function() {
#   assigned_to <- assign_to_study()[["study"]]
#   study_status <<- study_status %>%
#     mutate(num_judges = case_when(study == assigned_to ~ num_judges + 1, TRUE ~ num_judges))
#   return(assigned_to)
# }
# assignments_test <- tibble(iter = c(1:100)) %>%
#   mutate(study = map_chr(iter, ~ simulate_assignment()))
# study_status %>%
#   select(study, num_judges)

scripts <- read_yaml("vehicles.yml") %>%
  purrr::map(as_tibble_row) %>%
  enframe(name = NULL) %>%
  unnest(cols = c("value")) %>% 
  rename_with(~ str_replace(., "-", "_")) %>%
  rename(markdown = html) %>% 
  mutate(html = purrr::map(markdown, ~ markdown::markdownToHTML(
    text = .,
    fragment.only = TRUE
  ))) 




ui <- fluidPage(
  useShinyjs(),
  withMathJax(),
  
  tags$head(
    # Custom CSS
    tags$style(HTML("
      /* body {padding-top: 50px}  for the boostrap nav */
      /*ul.nav-pills {margin-top: 5px}*/
      @media (max-width: 768px) { .navbar-nav {float: left; margin: 5px; } }
      /*.navbar-nav {float: left; margin: 5px; }*/
      .navbar-text {float:left; margin-left:15px; }
      .navbar-right {float:right; margin-right:15px; }
      div#pageContent { margin-bottom: 2em; }
      #demographics .shiny-input-container { width: auto; clear: both; }
      #demographics .shiny-options-group { display: block; float: left; }
      #demographics .control-label { float: left; width: 12em; text-align: right; margin-right: 1em; }
      div.item_panel { padding: 1em 2em; border: 1px solid #ccc; box-shadow: 3px 4px 15px 0px #0000002b; overflow: auto;}
      div.item_content {margin-top: 1em; }
      #chooseLeft_comment-label, #chooseRight_comment-label { color: #999; font-weight: normal; font-style: italic; margin-top: 1em; }
      .comparison-image { width: 100%; }
    "))
  ),
  
  # Navbar
  #tags$div(class = "navbar navbar-default navbar-fixed-top",
  tags$div(class = "navbar navbar-default", style = "margin: -2px -15px",
           #tags$p(class = "navbar-text", id = "tab0", "Comparing proofs"),
           tags$p(class = "navbar-text", id = "tab0", actionLink("help", label = "Comparisons")),
           tags$ul(class = "nav navbar-nav nav-pills",
                   tags$li(role = "presentation", class = "disabled", id = "tab1",
                           tags$a(href = "#", "Step 1")),
                   tags$li(role = "presentation", class = "disabled", id = "tab2",
                           tags$a(href = "#", "Step 2")),
                   tags$li(role = "presentation", class = "disabled", id = "tab3",
                           tags$a(href = "#", "Step 3"))
           ),
           # tags$ul(class = "nav navbar-nav navbar-right",
           #         tags$li(role = "presentation", id = "help", tags$a(href = "#", icon("question-circle"))))
           # tags$ul(class = "nav navbar-nav navbar-right",
           #         tags$li(role = "presentation", id = "help", actionLink("help", label = icon("question-circle"))))
  ),
  # Version of the navbar done with pills
  # fluidRow(
  #   column(12, 
  #          tags$ul(class = "nav nav-pills",
  #                  tags$li(role = "presentation", class = "disabled", id = "tab0",
  #                          tags$a(href = "", tags$strong("Comparing proofs"))),
  #                  tags$li(role = "presentation", class = "disabled", id = "tab1",
  #                          tags$a(href = "#", "Step 1")),
  #                  tags$li(role = "presentation", class = "disabled", id = "tab2",
  #                          tags$a(href = "#", "Step 2")),
  #                  tags$li(role = "presentation", class = "disabled", id = "tab3",
  #                          tags$a(href = "#", "Step 3"))
  #           )
  #   )
  # ),
  tags$div(class = "clearfix"),
  
  # Placeholder for page content - the server will update this as needed
  uiOutput("pageContent")
)



server <- function(input, output, session) {
  
  # These will be global variables within each session
  assigned_study <- NULL
  session_info <- NULL
  prolific_id <- NULL
  judge_id <- NULL
  judging_method <- NULL
  
  # TODO - do something with the Prolific data
  observe({
    query <- parseQueryString(session$clientData$url_search)
    if (!is.null(query[['PROLIFIC_PID']])) {
      prolific_id <<- query[['PROLIFIC_PID']]
    } else {
      prolific_id <<- "None"
    }
  })
  
  all_scripts_html = scripts %>%
    mutate(html_out = purrr::map(html, ~ markdown::markdownToHTML(
      text = .,
      fragment.only = TRUE
    ))) %>% 
    mutate(html_out = paste0("<h2>Script ", item_num, "</h2>", html_out))
    
  #
  # Page 0 - consent form
  #
  output$pageContent <- renderUI({
    tagList(
      #p(paste("Judge group:", judge_group)),
      includeMarkdown("step0-participant-info.md"),
      #proofs %>% select(item_num) %>% display_item(),
      fluidRow(
        column(4, offset = 4, actionButton("consentButton", "I consent", class = "btn-success btn-lg btn-block", icon = icon("check")))
      ),
      h1("For debugging purposes, these are the scripts:"),
      paste(all_scripts_html$html_out, collapse = "") %>% HTML() %>% withMathJax()
    )
  })
 
  
  #
  # Page 1 - judging instructions
  #
  observeEvent(input$consentButton, {
    
    # Now they have consented, assign them to a condition
    assigned_study <<- assign_to_study()
    
    # Create session_info and synch with the judges table in the database
    ## 1. Write session info to the database
    session_info <<- tibble(
      shiny_info = session$token,
      shiny_timestamp = as.character(Sys.time()),
      study_id = assigned_study[["study"]],
      prolific_id = prolific_id,
    )
    dbWriteTable(pool,
                 "judges",
                 session_info,
                 row.names = FALSE,
                 append = TRUE)
    
    ## 2. Update session_info to include the autoincremented judge_id produced by the database
    session_info <<- pool %>% tbl("judges") %>%
      filter(shiny_info == !!session_info$shiny_info) %>%
      arrange(-judge_id) %>%
      collect() %>%
      slice(1)
    
    ## 3. Pick out the judge_id and judging_method for ease of reference later on
    judge_id <<- session_info$judge_id
    judging_method <<- assigned_study[["judging_method"]]
    print(judge_id)
    
    # update the nav
    shinyjs::addClass(id = "tab1", class = "disabled")
    shinyjs::removeClass(id = "tab1", class = "active")
    shinyjs::addClass(id = "tab2", class = "active")
    shinyjs::removeClass(id = "tab2", class = "disabled")
    
    # update the page content
    output$pageContent <- renderUI({
      tagList(
        h3("Instructions"),
        markdown::markdownToHTML(text = read_file(paste0("judging-instructions-", judging_method, ".md")),
                                 fragment.only = TRUE) %>% 
          str_replace("\\[JUDGING PROMPT\\]", assigned_study[["judging_prompt"]]) %>% HTML() %>% withMathJax(),
        fluidRow(
          column(4, offset = 4, actionButton("startComparing", "Start comparing", class = "btn-success btn-lg btn-block", icon = icon("check")))
        )
      )
    })
  })
  
  
  #
  # Judging
  #
  
  make_pairs <- function(pairs_to_make = 20) {
    
    # 1. Gather data on which judgements have been made already in this study group

    # all comparisons from this study
    judgement_data <- pool %>% 
      tbl("judgements") %>% 
      filter(study == !!session_info$study_id) %>% 
      select(-contains("comment")) %>% 
      collect() %>% 
      mutate(across(c("left", "right"), as.integer))

    # count the number of comparisons for each pair
    pairs_judged <- judgement_data %>%
      rowwise() %>%
      mutate(pair = paste(sort(c(left, right)), collapse = '_')) %>% 
      select(pair, judge_id) %>% 
      group_by(pair) %>% 
      tally() %>% 
      arrange(-n) %>% 
      separate(pair, c("s1", "s2"), "_") %>% 
      mutate(across(c("s1", "s2"), as.integer))
    
    # systematically list all pairs, and add the counts for each
    all_pairs_status <-
      crossing(scripts %>% select(s1 = item_num),
               scripts %>% select(s2 = item_num)) %>%
      filter(s1 < s2) %>%
      left_join(pairs_judged, by = c("s1", "s2")) %>%
      mutate(n = replace_na(n, 0))
    
    # 2. Select pairs from among the least judged so far
    
    pairs_to_judge <- tibble()
    
    while(nrow(pairs_to_judge) < pairs_to_make) {
      
      if(nrow(pairs_to_judge) == 0) {
        # start with the least judged pairs
        new_pairs_to_judge <- all_pairs_status %>% 
          filter(n == min(n)) %>% 
          slice_sample(n = pairs_to_make)
      } else {
        # but if we have selected some pairs already, remove them from
        # consideration (using anti_join) and look at the next-least-judged pairs
        new_pairs_to_judge <- all_pairs_status %>% 
          anti_join(pairs_to_judge, by = c("s1", "s2", "n")) %>% 
          filter(n == min(n)) %>% 
          slice_sample(n = pairs_to_make)
      }
      
      pairs_to_judge <- bind_rows(pairs_to_judge,
                                  new_pairs_to_judge)
    }
    
    return(pairs_to_judge %>%
             # trim to the desired number of pairs
             slice_head(n = pairs_to_make) %>% 
             # shuffle the scripts into left and right
             mutate(
               x = sample(c(0,1), size = pairs_to_make, replace = TRUE),
               left = ifelse(x==0, s1, s2),
               right = ifelse(x==0, s2, s1)
             ) %>% 
             select(left, right) %>%
             mutate(pair_num = row_number(), .before = 1)
    )
  }
  next_pair = function(old_pair_num) {
    # print("next_pair")
    # print(old_pair_num)
    # print(nrow(pairs))
    # move on to the next pair
    pair_to_return = old_pair_num + 1
    
    # if we've reached the end, add 20 more pairs to the list
    if(pair_to_return > nrow(pairs)) {
      pairs <<- pairs %>% bind_rows(make_pairs(pairs_to_make = 20) %>% mutate(pair_num = pair_num + old_pair_num))
      pair$pairs_available <- nrow(pairs)
      # print(pairs)
    }
    pairs %>% 
      filter(pair_num == pair_to_return) %>%
      head(1)
  }
  
  # initialise empty data structures, to be used when judging begins
  pair <- reactiveValues(
    pair_num = 0,
    pairs_available = 0,
    left = 1000,
    right = 1001
  )
  pairs <- tibble()
  
  observeEvent(input$startComparing, {
    
    pairs <<- make_pairs(pairs_to_make = 20)
    print(pairs)
    pair$pairs_available <- nrow(pairs)
  
    first_pair = pairs %>% head(1)
    pair$pair_num <- first_pair$pair_num
    pair$left <- first_pair$left
    pair$right <- first_pair$right

    # print(pair)
    # print("OK")

    # update the page content
    output$pageContent <- renderUI({
      tagList(
        h3(assigned_study[["judging_prompt"]]),
        htmlOutput("judging_progress"),
        fluidRow(
          column(6, htmlOutput("item_left")),
          column(6, htmlOutput("item_right"))
        ),
        fluidRow(
          htmlOutput("slider")
        ),
        # TODO - make this reset when each judgement is recorded
        fluidRow(
          textAreaInput("judging_comment", label = "Comments (optional)", width = "100%", height = "4em")
        )
      )
    })
    
    pair$start_time = Sys.time()
    print("Judging initialised")
    # print(pair)
  })
  
  display_item <- function(item_id) {
    the_item <- scripts %>% filter(item_num == item_id)
    if(str_length(the_item$html %>% as.character()) > 0) {
      return(the_item$html %>% as.character() %>% HTML() %>% withMathJax())
    } else {
      return(img(src = the_item$img_src, class = "comparison-image"))
    }
  }
  render_item_panel <- function(button_id, item_id) {
    # TODO - change this to deal with the slider condition
    tagList(
      div(class = "item_panel",
          fluidRow(
            actionButton(button_id, "Choose this one", class = "btn-block btn-primary")
          ),
          div(class = "item_content", display_item(item_id))
      )
    )
  }
  
  output$item_left <- renderUI({
    render_item_panel("chooseLeft", pair$left)
  })
  output$item_right <- renderUI({
    render_item_panel("chooseRight", pair$right)
  })
  
  output$judging_progress <- renderPrint({
    pc <- round((pair$pair_num -1) / 100 * 100)
    pc <- min(pc, 100)
    # https://getbootstrap.com/docs/3.4/components/#progress
    div(
      class = "progress",
      div(
        class = ifelse(pc < 100, "progress-bar", "progress-bar progress-bar-success"),
        role = "progressbar",
        `aria-valuenow` = pc,
        `aria-valuemin` = 0,
        `aria-valuemax` = 100,
        style = str_glue("min-width: 1em; width: {pc}%;"),
        pair$pair_num - 1
      )
    )
  })
  
  update_pair <- function() {
    new_pair <- next_pair(pair$pair_num)
    # print(new_pair)
    pair$pair_num <- new_pair$pair_num
    pair$left <- new_pair$left
    pair$right <- new_pair$right
    pair$start_time <- Sys.time()
  }
  
  record_judgement <- function(pair, winner = "left", loser = "right") {
    # TODO - split this into two versions, for binary/slider options i.e. record_judgement_slider should save the strength of choice to the `score` column
    # print(pair)
    print(paste(pair$left, pair$right, "winner:", winner))
    start_time <- pair$start_time
    current_time <- Sys.time()
    #print(start_time)
    #print(current_time)
    time_taken = as.integer((current_time - start_time) * 1000)
    
    winning_item = ifelse(winner == "left", pair$left, pair$right)
    losing_item = ifelse(loser == "left", pair$left, pair$right)
    
    dbWriteTable(
      pool,
      "judgements",
      tibble(
        study = session_info$study_id,
        judge_id = session_info$judge_id,
        left = pair$left,
        right = pair$right,
        won = winning_item,
        lost = losing_item,
        time_taken = time_taken,
        comment = input$judging_comment
      ),
      row.names = FALSE,
      append = TRUE
    )
  }
  observeEvent(input$chooseLeft, {
    record_judgement(pair, winner = "left", loser = "right")
    update_pair()
  })
  observeEvent(input$chooseRight, {
    record_judgement(pair, winner = "right", loser = "left")
    update_pair()
  })
  
  # Give a message when they reach the required number of comparisons
  # TODO - make this return them to the special Prolific landing page that will mark them as completed
  observe({
    if (pair$pair_num != 101) return()
    showModal(modalDialog(
      title = "Thank you!",
      p("You have now completed the 100 comparisons needed for the survey."),
      p("You can continue making further comparisons if you wish, and these will continue to be recorded."),
      p("When you are ready to stop, please simply close this browser window."),
      p("If you would like to receive an update about the results of the study, please complete this separate form:"),
      p(a("https://edinburgh.onlinesurveys.ac.uk/expert-opinions-about-proofs",
          target="_blank",
          href="https://edinburgh.onlinesurveys.ac.uk/expert-opinions-about-proofs"), style = "text-align: center;"),
      p("Thank you for taking part."),
      easyClose = TRUE
    ))
  })
  observeEvent(input$help, {
    showModal(modalDialog(
      title = "About this site",
      p("This study is being run by Dr George Kinnear,
        from the School of Mathematics at the University of Edinburgh."),
      p(HTML("If you have any questions about the study, please contact George:
        <a href=\"mailto:G.Kinnear@ed.ac.uk\">G.Kinnear@ed.ac.uk</a>.")),
      easyClose = TRUE
    ))
  })
  
}

shinyApp(ui, server)
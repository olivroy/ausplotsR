cache <- new.env(parent = emptyenv())

.ausplots_api <- function(path, query) {
  # override this API URL with:
  #   library("ausplotsR")
  #   options("ausplotsR_api_url" = "http://localhost:30000")
  #   ...continue to call functions
  auth_header <- ""
  the_role <- getOption("ausplotsR_role")
  the_secret <- getOption("ausplotsR_secret")
  if (!is.null(the_role) && !is.null(the_secret)) {
    path <- paste(path, "_inc_unpub", sep="")
    five_days <- 60 * 60 * 24 * 5
    exp_time <- as.integer(Sys.time() + five_days)
    claim <- jose::jwt_claim(role = the_role, exp = exp_time)
    jwt_val <- jose::jwt_encode_hmac(claim, secret = charToRaw(the_secret))
    auth_header <- paste('Bearer', jwt_val)
  }
  if (getOption("ausplotsR_api_debug", default = FALSE)) {
    message('query string value = ', query)
  }
  resp <- httr::GET(
                    getOption("ausplotsR_api_url", default= "http://swarmapi.ausplots.aekos.org.au:80"),
                    httr::user_agent(.make_user_agent()),
                    httr::add_headers(Authorization = auth_header),
                    path=path,
                    query=query
  )
  httr::stop_for_status(resp, task = httr::content(resp, "text"))
  if (httr::http_type(resp) != "application/json") {
    stop("API did not return json", call. = FALSE)
  }
  result <- try(jsonlite::fromJSON(httr::content(resp, "text"), simplifyDataFrame = TRUE))
  if(class(result) == "try-error") {
    stop("Data extraction aborted due to database connection issue.")
  }
  return(result)
}
################
#initial filter function
.ausplots_api_with_plot_filter <- function(path, Plot_IDs_to_filter_for, extra_query=list()) {
  query <- extra_query
  if (length(Plot_IDs_to_filter_for) > 0) {
    plotFilter <- paste("in.(", paste(Plot_IDs_to_filter_for, collapse=","), ")", sep="")
    query <- c(query, list(site_location_name = plotFilter))
  }
  return(.ausplots_api(path, query)) 
} 
################
#subsequent filter function

.ausplots_api_with_specified_plot_ids <- function(path, Plot_IDs_to_retrieve_data_for, extra_query=list()) {
  plotFilter <- paste("in.(", paste(Plot_IDs_to_retrieve_data_for, collapse=","), ")", sep="")
  query <- c(extra_query, list(site_location_name = plotFilter))
  return(.ausplots_api(path, query))
} 
################

list_available_plots <- function(Plot_IDs=c(), bounding_box="none", herbarium_determination_search=NULL, family_search=NULL, standardised_name_search=NULL) {
  extra_query <- list()
  
  if(!is.null(family_search)) {
    extra_query = append(extra_query, list("family" = paste("ilike.*", family_search, "*", sep=""))) #search by family
  }
  
  if(!is.null(herbarium_determination_search)) {
    extra_query = append(extra_query, list("herbarium_determination" = paste("ilike.*", herbarium_determination_search, "*", sep=""))) #search by herbarium_determination
  } 
  if(!is.null(standardised_name_search)) {
    extra_query = append(extra_query, list("standardised_name" = paste("ilike.*", standardised_name_search, "*", sep=""))) #search by standardised_name
  }
  if(Plot_IDs[1] == "none") {
    Plot_IDs <- c()
  }
  if(bounding_box[1] != "none") { #i.e. if user has supplied an extent vector
    if(class(bounding_box) != "numeric" | length(bounding_box) != 4) {stop("Bounding box must be a numeric vector of length 4.")}
    
    min_lon <- bounding_box[1]
    max_lon <- bounding_box[2]
    min_lat <- bounding_box[3]
    max_lat <- bounding_box[4]
    
    extra_query = append(extra_query, list("latitude" = paste("gte.", min_lat, sep="")))
    extra_query = append(extra_query, list("latitude" = paste("lte.", max_lat, sep="")))
    extra_query = append(extra_query, list("longitude" = paste("gte.", min_lon, sep="")))
    extra_query = append(extra_query, list("longitude" = paste("lte.", max_lon, sep="")))
  }

  path <- "search"
  response <- .ausplots_api_with_plot_filter(path, Plot_IDs, extra_query)
  result <- sort(unique(response$site_location_name))
  return(result)
}

################

extract_site_info <- function(Plot_IDs) {
  path <- "site"
  result <- .ausplots_api_with_specified_plot_ids(path, Plot_IDs)
  result$state = mapply(function(x) substr(x, 0, 2), result$site_location_name)
  result$state[result$state == "NS"] <- "NSW"
  result$state[result$state == "QD"] <- "QLD"
  result$state[result$state == "TC"] <- "TAS"
  result$state[result$state == "VC"] <- "VIC"
  
  return(result)
} 

###############

extract_struct_summ <- function(Plot_IDs) {
  path <- "structural_summary"
  return(.ausplots_api_with_specified_plot_ids(path, Plot_IDs))
} 

####################

extract_soil_subsites <- function(Plot_IDs) {
  path <- "soil_subsite"
  return(.ausplots_api_with_specified_plot_ids(path, Plot_IDs))
}

##################

extract_bulk_density <- function(Plot_IDs) {
  path <- "soil_bulk_density"
  return(.ausplots_api_with_specified_plot_ids(path, Plot_IDs))
}

##################

extract_soil_char <- function(Plot_IDs) {
  path <- "soil_characterisation"
  return(.ausplots_api_with_specified_plot_ids(path, Plot_IDs))
}

##################

extract_basal <- function(Plot_IDs, herbarium_determination_search=NULL, family_search=NULL, standardised_name_search=NULL) {
  extra_query <- list() 
   path <- "veg_basal"
   if(!is.null(family_search)) {
     extra_query = append(extra_query, list("family" = paste("ilike.*", family_search, "*", sep="")))#search by family 
   }
   if(!is.null(herbarium_determination_search)) {
     extra_query = append(extra_query, list("herbarium_determination" = paste("ilike.*", herbarium_determination_search, "*", sep=""))) #search by herbarium_determination
   } 
   if(!is.null(standardised_name_search)) { 
     extra_query = append(extra_query, list("standardised_name" = paste("ilike.*", standardised_name_search, "*", sep="")))#search by standardised_name
   } 
   return(.ausplots_api_with_specified_plot_ids(path, Plot_IDs, extra_query))
}

############################

extract_vouch <- function(Plot_IDs, herbarium_determination_search=NULL, family_search=NULL, standardised_name_search=NULL) {
  extra_query <- list()
  path <- "veg_voucher"
  if(!is.null(family_search)) {
    extra_query = append(extra_query, list("family" = paste("ilike.*", family_search, "*", sep="")))#search by family 
  }
  if(!is.null(herbarium_determination_search)) {
    extra_query = append(extra_query, list("herbarium_determination" = paste("ilike.*", herbarium_determination_search, "*", sep=""))) #search by herbarium_determination
  } 
  if(!is.null(standardised_name_search)) { 
    extra_query = append(extra_query, list("standardised_name" = paste("ilike.*", standardised_name_search, "*", sep="")))#search by standardised_name
  } 
  return(.ausplots_api_with_specified_plot_ids(path, Plot_IDs, extra_query))
}

############################

extract_hits <- function(Plot_IDs) {
  path <- "veg_pi"
  return(.ausplots_api_with_specified_plot_ids(path, Plot_IDs))
}

############################

cache$user_agent <- NULL

.make_user_agent <- function() {
  # thanks https://github.com/r-lib/httr/blob/af25ebd0e3b72d2dc6e1423242b94efc25bc97cc/R/config.r#L137
  if (is.null(cache$user_agent)) {
    if (getOption("ausplotsR_api_debug", default = FALSE)) {
      message('building user_agent string and storing in cache')
    }
    versions <- c(
                  ausplotsR = as.character(utils::packageVersion("ausplotsR")),
                  libcurl = curl::curl_version()$version,
                  `r-curl` = as.character(utils::packageVersion("curl")),
                  httr = as.character(utils::packageVersion("httr"))
    )
    result <- paste0(names(versions), "/", versions, collapse = " ")
    cache$user_agent <- result
  }
  cache$user_agent
}

############################

cache$metadata_dictionary <- NULL

.get_metadata_dictionary <- function(force_refresh = FALSE) {
  if (is.null(cache$metadata_dictionary) || force_refresh) {
    if (getOption("ausplotsR_api_debug", default = FALSE)) {
      message('refreshing metadata_dictionary and storing in cache')
    }
    path <- "metadata-dictionary.json"
    result <- .ausplots_api(path, NULL)
    cache$metadata_dictionary <- result
  }
  cache$metadata_dictionary
}


################################

descr_out <- function(descr, ret_type = "html") {
  ## if there is no data description
  if (is_empty(descr)) return("")

  ## if there is a data description and we want html output
  if (ret_type == "html") {
    markdown::markdownToHTML(text = descr, stylesheet = "")
  } else {
    descr
  }
}

## create an empty data.frame and return error message as description
upload_error_handler <- function(objname, ret) {
  r_data[[objname]] <<- data.frame(matrix(rep("", 12), nrow = 2), stringsAsFactors = FALSE) %>% 
    set_attr("description", ret)
}

loadClipboardData <- function(objname = "copy_and_paste", ret = "", header = TRUE, sep = "\t") {
  dat <- sshhr(try({
    if (Sys.info()["sysname"] == "Windows") {
      read.table("clipboard", header = header, sep = sep, comment.char = "", fill = TRUE, as.is = TRUE)
    } else if (Sys.info()["sysname"] == "Darwin") {
      read.table(pipe("pbpaste"), header = header, sep = sep, comment.char = "", fill = TRUE, as.is = TRUE)
    } else {
      if (!is_empty(input$load_cdata)) {
        read.table(text = input$load_cdata, header = header, sep = sep, comment.char = "", fill = TRUE, as.is = TRUE)
      }
    }
  } %>% as.data.frame(check.names = TRUE, stringsAsFactors = FALSE), silent = TRUE))

  if (is(dat, "try-error") || nrow(dat) == 0) {
    if (ret == "") ret <- c("### Data in clipboard was not well formatted. Try exporting the data to csv format.")
    upload_error_handler(objname, ret)
  } else {
    ret <- paste0("### Clipboard data\nData copied from clipboard on ", lubridate::now())
    colnames(dat) <- make.names(colnames(dat))
    r_data[[objname]] <- factorizer(dat)
  }

  r_data[[paste0(objname, "_descr")]] <- ret
  r_data[["datasetlist"]] <- c(objname, r_data[["datasetlist"]]) %>% unique()
}

saveClipboardData <- function() {
  os_type <- Sys.info()["sysname"]
  if (os_type == "Windows") {
    write.table(.getdata(), "clipboard-10000", sep = "\t", row.names = FALSE)
  } else if (os_type == "Darwin") {
    write.table(.getdata(), file = pipe("pbcopy"), row.names = FALSE, sep = "\t")
  } else if (os_type == "Linux") {
    print("### Saving data through the clipboard is currently only supported on Windows and Mac. You can save your data to csv format to use it in a spreadsheet.")
  }
}

loadUserData <- function(
  fname, uFile, ext, header = TRUE,
  man_str_as_factor = TRUE, sep = ",", dec = ".", 
  n_max = Inf
) {

  filename <- basename(fname)
  fext <- tools::file_ext(filename) %>% tolower()

  ## switch extension if needed
  if (fext == "rdata") ext <- "rdata"
  if (fext == "rds" && ext == "rda") ext <- "rds"
  if (fext == "rda" && ext == "rds") ext <- "rda"
  if (fext == "rdata" && ext == "rds") ext <- "rdata"
  if (fext == "txt" && ext == "csv") ext <- "txt"
  if (fext == "tsv" && ext == "csv") ext <- "tsv"

  ## objname is used as the name of the data.frame, make case insensitive
  objname <- sub(paste0(".", ext, "$"), "", filename, ignore.case = TRUE)

  ## if ext isn't in the filename nothing was replaced and so ...
  if (objname == filename) {
    if (fext %in% c("xls", "xlsx")) {
      ret <- "### Radiant does not load xls files directly. Please save the data as a csv file and try again."
    } else {
      ret <- paste0("### The filename extension (", fext, ") does not match the specified file-type (", ext, "). Please specify the file type you are trying to upload (i.e., csv or rda).")
    }

    upload_error_handler(objname, ret)
    ext <- "---"
  }

  if (ext %in% c("rda", "rdata")) {
    ## objname will hold the name of the object(s) inside the R datafile
    robjname <- try(load(uFile), silent = TRUE)
    if (is(robjname, "try-error")) {
      upload_error_handler(objname, "### There was an error loading the data. Please make sure the data are in rda format.")
    } else if (length(robjname) > 1) {
      if (sum(robjname %in% c("r_state", "r_data")) == 2) {
        upload_error_handler(objname, "### To restore state from a state-file select 'state' from the 'Load data of type' drowdown before uploading the file")
        rm(r_state, r_data) ## need to remove the local copies of r_state and r_data
      } else {
        upload_error_handler(objname, "### More than one R object contained in the data.")
      }
    } else {
      r_data[[objname]] <- as.data.frame(get(robjname), stringsAsFactors = FALSE) %>% {
        set_colnames(., make.names(colnames(.)))
      }
    }
  } else if (ext == "rds") {
    ## objname will hold the name of the object(s) inside the R datafile
    robj <- try(readRDS(uFile), silent = TRUE)
    if (is(robj, "try-error")) {
      upload_error_handler(objname, "### There was an error loading the data. Please make sure the data are in rds format.")
    } else {
      r_data[[objname]] <- as.data.frame(robj, stringsAsFactors = FALSE) %>% {
        set_colnames(., make.names(colnames(.)))
      }
    }
  } else if (ext == "feather") {
    if (!"feather" %in% rownames(utils::installed.packages())) {
      upload_error_handler(objname, "### The feather package is not installed. Please use install.packages('feather')")
    } else {
      robj <- feather::read_feather(uFile) %>%
        set_attr("description", feather::feather_metadata(uFile)$description)
      if (is(robj, "try-error")) {
        upload_error_handler(objname, "### There was an error loading the data. Please make sure the data are in feather format.")
      } else {
        r_data[[objname]] <- robj %>% {
          set_colnames(., make.names(colnames(.)))
        }
      }
    }
  } else if (ext %in% c("tsv", "csv", "txt")) {
    r_data[[objname]] <- loadcsv(uFile, header = header, n_max = n_max, sep = sep, dec = dec, saf = man_str_as_factor) %>% {
      if (is.character(.)) upload_error_handler(objname, "### There was an error loading the data") else .
    } %>% {
      set_colnames(., make.names(colnames(.)))
    }
  } else if (ext != "---") {
    ret <- paste0("### The selected filetype is not currently supported (", fext, ").")
    upload_error_handler(objname, ret)
  }

  r_data[[paste0(objname, "_descr")]] <- attr(r_data[[objname]], "description")
  r_data[["datasetlist"]] <<- c(objname, r_data[["datasetlist"]]) %>% unique()
}

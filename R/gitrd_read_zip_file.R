#' Reads a single zip file downloaded from Bovespa
#'
#' @param my.zip.file Full path to zip file
#' @param folder.to.unzip Folder to unzip files (default = tempdir())
#' @param id.type The type of file structure ('after 2011' or 'before 2011')
#' @param type.fin.report Peridodicy of fin data ('itr' - quarterly or 'dfp' - annual)
#'
#' @return A list with several dataframes containing financial statements
#' @export
#'
#' @examples
#'
#' my.f <- system.file('extdata/434_ARAC_2008-09-30.zip', package = 'GetITRData')
#'
#' my.l <- gitrd.read.zip.file(my.f, id.type = 'before 2011', type.fin.report = 'itr')
#' print(my.l)
gitrd.read.zip.file <- function(my.zip.file,
                                folder.to.unzip = tempdir(),
                                id.type,
                                type.fin.report) {

  # sanity check
  if (tools::file_ext(my.zip.file) != 'zip') {
    stop(paste('File', my.zip.file, ' is not a zip file.') )
  }

  if (!file.exists(my.zip.file)) {
    stop(paste('File', my.zip.file, ' does not exists.') )
  }

  if (file.size(my.zip.file) == 0){
    stop(paste('File', my.zip.file, ' has size 0!') )
  }

  if (length(my.zip.file) != 1){
    stop('This function only works for a single zip file... check your inputs')
  }

  if (!dir.exists(folder.to.unzip)) {
    cat(paste('Folder', folder.to.unzip, 'does not exist. Creating it.'))
    dir.create(folder.to.unzip)
  }

  my.basename <- tools::file_path_sans_ext(basename(my.zip.file))
  rnd.folder.name <- file.path(folder.to.unzip, paste0('DIR-',my.basename))

  if (!dir.exists(rnd.folder.name)) dir.create(rnd.folder.name)

  utils::unzip(my.zip.file, exdir = rnd.folder.name, junkpaths = TRUE)

  # list files and check it
  my.files <- list.files(rnd.folder.name)

  if (length(my.files) == 0) {
    #browser()

    file.remove(my.zip.file)
    stop(paste0('Zipped file contains 0 files. ',
                'This is likelly a problem with the downloaded file. ',
                'Try running the code again as the corrupted zip file was deleted and will be downloaded again.',
                '\n\nIf the problem persists, my suggestions is to remove the time period with problem.') )
  }

  if (id.type == 'after 2011') {
    my.l <- gitrd.read.zip.file.type.1(rnd.folder.name, folder.to.unzip, type.fin.report)
  }

  if (id.type == 'before 2011') {
    my.l <- gitrd.read.zip.file.type.2(rnd.folder.name, folder.to.unzip, type.fin.report)
  }

  # check for empty dfs
  my.fct <- function(df.in) {
    if (nrow(df.in)==0) {
      df.out <- data.frame(acc.number = NA, acc.desc = NA, acc.value = NA)
    } else {
      df.out <- df.in
    }
    return(df.out)
  }

  my.l$cons.dfs <- lapply(my.l$cons.dfs, my.fct)
  my.l$ind.dfs  <- lapply(my.l$ind.dfs , my.fct)

  return(my.l)
}

#' Reads folder for zip file post 2011 (internal)
#'
#' @inheritParams gitrd.read.zip.file
#' @param rnd.folder.name Folder where unzipped files are available
#'
#' @return A list with financial statements
#'
#' @examples
#' # no example (this functions not used directly)
gitrd.read.zip.file.type.1 <- function(rnd.folder.name, folder.to.unzip = tempdir(), type.fin.report) {

  company.reg.file <- switch(type.fin.report,
                             'itr' = file.path(rnd.folder.name,'FormularioDemonstracaoFinanceiraITR.xml'),
                             'dfp' = file.path(rnd.folder.name,'FormularioDemonstracaoFinanceiraDFP.xml') )

  xml_data <- XML::xmlToList(XML::xmlParse(company.reg.file))

  # get basic info

  company.name = xml_data$CompanhiaAberta$NomeRazaoSocialCompanhiaAberta
  company.cvm_code <- xml_data$CompanhiaAberta$CodigoCvm
  company.SeqNumber <- xml_data$CompanhiaAberta$NumeroSequencialRegistroCvm
  company.date.delivery <- xml_data$DataEntrega
  date.docs <- as.Date(xml_data$DataReferenciaDocumento, format = '%Y-%m-%d')

  #cat('\nReading', my.zip.file, '-', company.name, '|', as.character(date.docs))

  zipped.file <- switch(type.fin.report,
                             'itr' = file.path(rnd.folder.name, list.files(rnd.folder.name, pattern = '*.itr')[1]),
                             'dfp' = file.path(rnd.folder.name, list.files(rnd.folder.name, pattern = '*.dfp')[1]) )

  utils::unzip(zipped.file, exdir = rnd.folder.name)

  fin.report.file <- file.path(rnd.folder.name, 'InfoFinaDFin.xml')

  if (!file.exists(fin.report.file)) {
    stop('Cant find file', fin.report.file)
  }

  xml_data <- XML::xmlToList(XML::xmlParse(fin.report.file))

  file.remove(fin.report.file)

  # function to get individual DF
  my.fct <- function(x, type.df, info){

    if (type.df == 'individual') my.char = '1'
    if (type.df == 'consolidated') my.char = '2'

    if (x$PlanoConta$VersaoPlanoConta$CodigoTipoInformacaoFinanceira == my.char){

      if (info == 'Descricao') return(x$DescricaoConta1)
      if (info == 'Valor') {


        my.value <- switch(type.fin.report,
                           'itr' = as.numeric(c(x$ValorConta2, x$ValorConta3, x$ValorConta4)),
                           'dfp' = as.numeric(c(x$ValorConta1, x$ValorConta2, x$ValorConta3,x$ValorConta4))
                           )

        my.value <- my.value[my.value != 0]
        if (length(my.value)==0) {
          my.value <- 0
        } else {
          my.value <- my.value[1]
        }

        return(my.value)
      }
      if (info == 'id') return(x$PlanoConta$NumeroConta)

    } else {
      return(NA)
    }
  }

  # get individual dfs
  type.df <- 'individual'
  acc.desc  <- as.character(sapply(xml_data, my.fct, type.df = type.df, info = 'Descricao'))
  acc.value <-   as.numeric(sapply(xml_data, my.fct, type.df = type.df, info = 'Valor'))
  acc.number <- as.character(sapply(xml_data, my.fct, type.df = type.df, info = 'id'))

  ind.df <- data.frame(acc.number,acc.desc,acc.value)

  # save info
  df.assets <- stats::na.omit(ind.df[stringr::str_sub(ind.df$acc.number,1,1) == '1', ])
  df.liabilities <- stats::na.omit(ind.df[stringr::str_sub(ind.df$acc.number,1,1) == '2', ])
  df.income    <- stats::na.omit(ind.df[stringr::str_sub(ind.df$acc.number,1,1) == '3', ])
  df.cashflow    <- stats::na.omit(ind.df[stringr::str_sub(ind.df$acc.number,1,1) == '6', ])

  l.individual.dfs <- list(df.assets = df.assets,
                           df.liabilities = df.liabilities,
                           df.income = df.income,
                           df.cashflow = df.cashflow)

  # get consolidated dfs
  type.df <- 'consolidated'
  acc.desc  <- as.character(sapply(xml_data, my.fct, type.df = type.df, info = 'Descricao'))
  acc.value <-   as.numeric(sapply(xml_data, my.fct, type.df = type.df, info = 'Valor'))
  acc.number <- as.character(sapply(xml_data, my.fct, type.df = type.df, info = 'id'))

  consolidated.df <- data.frame(acc.number,acc.desc,acc.value)

  # save info
  df.assets <- stats::na.omit(consolidated.df[stringr::str_sub(consolidated.df$acc.number,1,1) == '1', ])
  df.liabilities <- stats::na.omit(consolidated.df[stringr::str_sub(consolidated.df$acc.number,1,1) == '2', ])
  df.income    <- stats::na.omit(consolidated.df[stringr::str_sub(consolidated.df$acc.number,1,1) == '3', ])
  df.cashflow    <- stats::na.omit(consolidated.df[stringr::str_sub(consolidated.df$acc.number,1,1) == '6', ])

  l.consolidated.dfs <- list(df.assets = df.assets,
                             df.liabilities = df.liabilities,
                             df.income = df.income,
                             df.cashflow = df.cashflow)

  my.l <- list(ind.dfs = l.individual.dfs,
               cons.dfs = l.consolidated.dfs)

  return(my.l)
}

#' Reads folder for zip file pre 2011 (internal)
#'
#' @inheritParams gitrd.read.zip.file
#' @param rnd.folder.name Folder where unzipped files are available
#'
#' @return A list with financial statements
#'
#' @examples
#' # no example (this functions not used directly)
gitrd.read.zip.file.type.2 <- function(rnd.folder.name, folder.to.unzip = tempdir(), type.fin.report) {


  # get individual fin statements
  #my.f <- file.path(rnd.folder.name, '/ITRBPAE.001')

  my.f <- switch(type.fin.report,
                 'itr' = list.files(rnd.folder.name,'ITRBPAE', full.names = T),
                 'dfp' = list.files(rnd.folder.name,'DFPBPAE', full.names = T))

  df.assets <- gitrd.read.fwf.file(my.f, type.fin.report)

  #my.f <- paste0(rnd.folder.name,'/ITRBPPE.001')
  my.f <- switch(type.fin.report,
                 'itr' = list.files(rnd.folder.name, pattern = 'ITRBPP', full.names = T),
                 'dfp' = list.files(rnd.folder.name, 'DFPBPPE', full.names = T) )

  df.liabilities <- gitrd.read.fwf.file(my.f, type.fin.report)


  my.f <- switch(type.fin.report,
                 'itr' = list.files(rnd.folder.name, pattern = 'ITRDERE', full.names = T),
                 'dfp' = list.files(rnd.folder.name, 'DFPDEREE', full.names = T) )
  df.income <- gitrd.read.fwf.file(my.f, type.fin.report)


  my.f <- switch(type.fin.report,
                 'itr' = list.files(rnd.folder.name, pattern = 'ITRDFCE', full.names = T),
                 'dfp' = list.files(rnd.folder.name, 'DFPDFCEE', full.names = T) )
  if (length(my.f) == 0) {
    df.cashflow <- data.frame(acc.desc  = NA,
                              acc.value = NA,
                              acc.number = NA)
  }else {
    df.cashflow <- gitrd.read.fwf.file(my.f, type.fin.report)
  }

  l.individual.dfs <- list(df.assets = df.assets,
                           df.liabilities = df.liabilities,
                           df.income = df.income,
                           df.cashflow = df.cashflow)


  # get consolidated fin statements

  #my.f <- paste0(rnd.folder.name,'/ITRCBPAE.001')
  my.f <- switch(type.fin.report,
                 'itr' = list.files(rnd.folder.name,'ITRCBPA', full.names = T),
                 'dfp' = list.files(rnd.folder.name,'DFPCBPAE', full.names = T))
  df.assets <- gitrd.read.fwf.file(my.f, type.fin.report)


  my.f <- switch(type.fin.report,
                 'itr' = list.files(rnd.folder.name,'ITRCBPP', full.names = T),
                 'dfp' = list.files(rnd.folder.name,'DFPCBPPE', full.names = T))
  df.liabilities <- gitrd.read.fwf.file(my.f, type.fin.report)


  my.f <- switch(type.fin.report,
                 'itr' = list.files(rnd.folder.name,'ITRCDER', full.names = T),
                 'dfp' = list.files(rnd.folder.name,'DFPCDERE', full.names = T))
  df.income <- gitrd.read.fwf.file(my.f, type.fin.report)


  my.f <- switch(type.fin.report,
                 'itr' = list.files(rnd.folder.name,'ITRCDFCE', full.names = T),
                 'dfp' = list.files(rnd.folder.name,'DFPCDFCEE', full.names = T))

  if (length(my.f) == 0) {
    df.cashflow <- data.frame(acc.desc  = NA,
                              acc.value = NA,
                              acc.number = NA)
  } else {
    df.cashflow <- gitrd.read.fwf.file(my.f, type.fin.report)
  }

  l.consolidated.dfs<- list(df.assets = df.assets,
                           df.liabilities = df.liabilities,
                           df.income = df.income,
                           df.cashflow = df.cashflow)
  # get basic info

  my.l <- list(ind.dfs = l.individual.dfs,
               cons.dfs = l.consolidated.dfs)

  return(my.l)
}

#' @title Plot Acoustic Scene
#'
#' @description Plots a representation of the acoustic scene using
#'   detections in data. Frequency ranges for detections are taken
#'   from user input and displayed as different colored bars
#'
#' @param x dataframe of detections, must have column \code{UTC} and
#'   a column to connect detection types to the frequency type map
#' @param freqMap a dataframe listing frequency ranges to use for
#'   various detection types in \code{x}. Must have columns \code{type},
#'   \code{freqMin} (Hz), \code{freqMax} (Hz), and optionally \code{color}
#'   (color to use for this type of detection on plot)
#' @param typeCol column name in \code{x} that matches names in \code{type}
#'   column in \code{freqMap}
#' @param title optional title to use for the plot
#' @param bin time bin to use for plotting time axis. Each detection will
#'   be displayed as covering this amount of time
#' @param scale one of \code{log} or \code{linear}, the frequency scale for
#'   the plot
#' @param freqMin optional minimum frequency for plot, useful for log scale
#' @param freqMax optional maximum frequency for plot
#' @param fill logical flag if \code{TRUE} then filled boxes will be plotted,
#'   if \code{FALSE} then only outlines will be plotted
#' @param alpha transparency percentage for plotting, values less than 1
#'   will allow multiple overlapping colors to be seen
#' @param returnData if \code{TRUE} then no plot will be generated, instead the
#'   dataframe that would normally be used to make the plot will be returned
#' @param add logical flag if \code{FALSE} plots normally if \code{TRUE}
#'   then the output can be (maybe) added to an existing ggplot object
#'
#' @return a ggplot object
#'
#' @author Taiki Sakai \email{taiki.sakai@@noaa.gov}
#'
#' @examples
#' detDf <- data.frame(
#'    UTC=as.POSIXct(c('2023-01-01 00:00:00',
#'                     '2023-01-03 00:00:00',
#'                     '2023-01-02 12:00:00',
#'                     '2023-01-04 00:00:00'),
#'                   tz='UTC'),
#'   species = c('Dolphin', 'Whale', 'Whale', 'Dolphin'))
#' freqMap <- data.frame(type=c('Dolphin', 'Whale'),
#'                       freqMin=c(10e3, 100),
#'                       freqMax=c(30e3, 400),
#'                       color=c('darkgreen', 'blue'))
#' plotAcousticScene(detDf, freqMap=freqMap, typeCol='species', bin='1day')
#'
#' @importFrom dplyr left_join join_by distinct
#'
#' @export
#'
plotAcousticScene <- function(x, freqMap, typeCol='species',
                              title=NULL, bin='1day', scale=c('log', 'linear'),
                              freqMin=NULL, freqMax=NULL,
                              fill=TRUE,
                              alpha=1, returnData=FALSE, add=FALSE) {
    x <- checkSimple(x, needCols=c('UTC', typeCol))
    x$plotStart <- floor_date(x$UTC, unit=bin)
    thisPeriod <- unitToPeriod(bin)
    x$plotEnd <- x$plotStart + thisPeriod
    scale <- switch(match.arg(scale),
                    'log' = 'log10',
                    'identity'
    )
    missType <- unique(x[[typeCol]])[!unique(x[[typeCol]]) %in% freqMap$type]
    if(length(missType) > 0) {
        warning(length(missType), ' types in "x$', typeCol, '" were not in "freqMap$type" (',
                paste0(missType, collapse=', '), '), they will not be plotted.',
                call.=FALSE)
        x <- x[!x[[typeCol]] %in% missType, ]
    }
    # jank-ish work around to work with NSE for join_by, {{ }} didnt work
    x$TEMPJOINCOLUMN <- x[[typeCol]]
    x <- left_join(x, freqMap, by=join_by('TEMPJOINCOLUMN' =='type'))
    x$TEMPJOINCOLUMN <- NULL

    x <- x[!is.na(x[['freqMin']]), ]
    x <- distinct(x[c('plotStart', 'plotEnd', 'freqMin', 'freqMax', typeCol)])
    x <- bind_rows(lapply(split(x, x[[typeCol]]), function(d) {
        if(nrow(d) == 1) {
            return(d)
        }
        d$difftime <- TRUE
        d$difftime[2:nrow(d)] <- d$plotStart[2:nrow(d)] != d$plotEnd[1:(nrow(d)-1)]
        d$group <- cumsum(d$difftime)
        # d <- group_by(d, .data$group, .data[[typeCol]], .data$freqMin, .data$freqMax) %>%
        #     summarise(plotStart = min(.data$plotStart),
        #               plotEnd = max(.data$plotEnd)) %>%
        #     ungroup()
        d <- ungroup(
            summarise(
                group_by(d, .data$group, .data[[typeCol]], .data$freqMin, .data$freqMax),
                plotStart = min(.data$plotStart),
                plotEnd = max(.data$plotEnd)
            )
        )
        d$group <- NULL
        d
    }))
    if(isTRUE(returnData)) {
        return(x)
    }
    if(is.null(freqMin)) {
        freqMin <- min(x[['freqMin']])
    }
    if(is.null(freqMax)) {
        freqMax <- max(x[['freqMax']])
    }
    if(freqMin < 1 && scale == 'log10') {
        freqMin <- 1
    }
    if(isFALSE(add)) {
        g <- ggplot()
    } else {
        if(!inherits(add, 'ggplot')) {
            stop('"add" must be FALSE or a ggplot object')
        }
        g <- add
        fill <- FALSE
    }
    if(isTRUE(fill)) {
        g <- g +
            geom_rect(data=x,
                      aes(xmin=.data$plotStart,
                          xmax=.data$plotEnd,
                          ymin=.data$freqMin,
                          ymax=.data$freqMax,
                          fill=.data[[typeCol]]),
                      alpha=alpha)
    } else { # or only color
        g <- g +
            geom_rect(data=x,
                      aes(xmin=.data$plotStart,
                          xmax=.data$plotEnd,
                          ymin=.data$freqMin,
                          ymax=.data$freqMax,
                          color=.data[[typeCol]]),
                      fill=NA,
                      alpha=alpha)
    }
    # g <- g +
    #     scale_x_datetime()
    # scale_y_continuous(trans=scale)

    if(isFALSE(add)) {
        if(scale == 'log10') {
            g <- myLog10Scale(g, range=c(freqMin, freqMax), dim='y')
        }
        g <- g +
            ggtitle(title) +
            labs(y='Frequency (Hz)',
                 x='Date',
                 fill='Sound Type') +
            scale_x_datetime()

    }
    if('color' %in% colnames(freqMap)) {
        colNames <- freqMap[['color']]
        names(colNames) <- freqMap[['type']]
        if(isTRUE(fill)) {
            g <- g +
                scale_fill_manual(values=colNames, name='Sound Type')
        } else {
            g <- g +
                scale_color_manual(values = colNames, name='Sound Type')
        }
    }
    g
}

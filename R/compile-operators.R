# tangram a general purpose table toolkit for R
# Copyright (C) 2017 Shawn Garbett
# 
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

  #############################################################################
 ##
## Set of functions to use in building a table, cell by cell

#' Derive label of AST node.
#'
#' Determine the label of a given AST node.
#' NOTE: Should have data attached via reduce before calling.
#'
#' @param node Abstract syntax tree node.
#'
#' @return A string with a label for the node
#' @include compile-cell.R
#' @export
derive_label <- function(node)
{
  l <- node$name()
  units <- NA
  try({
        l2 <- attr(node$data, "label")
        if(!is.null(l2))
        {
          # Since a label was found, see if it has units
          u2 <- str_match(l2, "(.*)\\((.*)\\)")
          if(is.na(u2[1,1]))
          {
            l <- l2
          } else {
            l     <- u2[1,2]
            units <- u2[1,3]
          }
        }
  })

  # Find units if they exist
  try({
    u2 <- attr(node$data, "units")

    if(!is.null(u2)) {units<-u2}
  })

  cell_label(l, units)
}

  #############################################################################
 ##
## Helper functions for adding headers

#' Flatten variable arguments
#'
#' Take variable arguments, flatten vectors and lists, but do not flatten cells (which are lists)
#' e.g. args_flatten(NA, list(1,2,3), 4:6, c(7,8,9))
#'
#' @param ... variable arguments
#' @return a list of the arguments, with vectors and lists flattened
#'
args_flatten <- function(...)
{
  ls   <- list(...)
  flat <- list()
  el   <- 1

  for(a in ls)
  {
    if("list" %in% class(a) || is.vector(a) || "N" %in% class(a))
    {
      for(b in a)
      {
        flat[[el]] <- b
        if(!"list" %in% class(a))
        {
          class(flat[[el]]) <- class(a)
          names(flat[[el]]) <- names(a)
        }
        el <- el+1
      }
    } else {
      flat[[el]] <- a
      el <- el + 1
    }
  }
  flat
}

#' Create a new header on a table
#'
#' Function to append a header object to a given attribute. Will create
#' a new header if one doesn't exit, or append to existing
#'
#' @param table_builder The table builder object to modify
#' @param attribute The header attribute name, i.e. row_header or col_header
#' @param sub boolean indicating if this is a subheader
#' @param ... All the header elements to add
#' @return the modified table_builder
#'
new_header <- function(table_builder, attribute, sub, ...)
{
  # Grab old header if it exists
  old_hdr   <- attr(table_builder$table, attribute)

  # Either a header or subheader
  hdr_class <- if (is.null(old_hdr) | !sub) "cell_header" else c("cell_subheader", "cell_header")

  # Convert every element to an appropriate cell from request
  new_hdr   <- lapply(args_flatten(...), FUN=function(x) {
    value <-   cell(x, row=table_builder$row, col=table_builder$col)
    attr(value, "class") <- c(hdr_class, attr(value,"class"))
    value
  })

  # If the old header is null, then create one
  attr(table_builder$table, attribute) <- if(is.null(old_hdr))
  {
    header <- list(new_hdr)
    attr(header, "class")    <- c("cell_table", "cell")
    attr(header, "embedded") <- FALSE
    header
  } else { # extend existing
    old_hdr[[length(old_hdr)+1]] <- new_hdr
    old_hdr
  }

  # Return table_builder for pipe operator
  table_builder
}

#' Create a new column header in a table
#'
#' Function to append a column header to a table being built. The first call creates
#' a column header, subsequent calls add sub headers to existing column header
#'
#' @param table_builder The table builder object to modify
#' @param ... All the column header elements to add
#' @param sub treat as subheader if after first header, defaults to TRUE
#' @return the modified table_builder
#' @export
#'
col_header <- function(table_builder, ..., sub=TRUE) new_header(table_builder, "col_header", sub, ...)

#' Create a new row header in a table.
#'
#' Function to append a row header to a table being built. The first call creates
#' a row header, subsequent calls add sub headers to existing row header
#'
#' @param table_builder The table builder object to modify
#' @param ... All the row header elements to add
#' @param sub treat as subheader if after first, default to TRUE
#' @return the modified table_builder
#' @export
#'
row_header <- function(table_builder, ..., sub=TRUE) new_header(table_builder, "row_header", sub, ...)

  #############################################################################
 ##
## Table cursor, movement and manipulation. Loosely based on VT100


#' Create empty table builder.
#'
#' Function to create a new table builder to use in continuations.
#' This maintains a cursor state where values are being written to the
#' table under construction, as well as references to the row and column
#' for automated tracability when generating indexes.
#'
#' @param row The row node from the AST
#' @param column The col node from the AST
#' @return a table builder with 1 empty cell at position (1,1)
#' @export
#'
#' @examples
#' x <- Parser$new()$run(y ~ x)
#' new_table_builder(x$right, x$left)
#'
new_table_builder <- function(row, column)
{
  list(nrow=1, ncol=1, table=cell_table(1,1), row=row, col=column)
}

#' Write a single cell
#'
#' Function to write a value to the current position in the table builder
#'
#' @param table_builder The table builder to work on
#' @param x the cell to write
#' @param ... additional attributes to pass for traceback
#' @return a table builder with the given cell written in the current cursor position
#' @export
#'
#' @examples
#' library(magrittr)
#' x <- Parser$new()$run(y ~ x)
#' new_table_builder(x$right, x$left) %>% write_cell(tg_N(23))
#'
write_cell <- function(table_builder, x, ...)
{
  if(table_builder$nrow > length(table_builder$table))
  {
    table_builder$table[[table_builder$nrow]] <- list()
  }
  table_builder$table[[table_builder$nrow]][[table_builder$ncol]] <- cell(x, row=table_builder$row, col=table_builder$col, ...)
  table_builder
}

#' Home the cursor.
#'
#' Return table builder cursor position to (1,1)
#'
#' @param table_builder The table builder to work on
#' @return a table builder with the cursor at home
#' @export
#'
#' @examples
#' library(magrittr)
#' x <- Parser$new()$run(y ~ x)
#' new_table_builder(x$right, x$left) %>% home()
#'
home <- function(table_builder)
{
  table_builder$ncol <- 1
  table_builder$nrow <- 1
  table_builder
}

#' Move cursor up
#'
#' Move table builder cursor up specified value (default 1)
#'
#' @param table_builder The table builder to work on
#' @param n units to move cursor up
#' @return a table builder with the cursor up n positions
#' @export
#'
#' @examples
#' library(magrittr)
#' x <- Parser$new()$run(y ~ x)
#' new_table_builder(x$right, x$left) %>% cursor_pos(3,3) %>% cursor_up(2)
#'
cursor_up <- function(table_builder, n=1)
{
  table_builder$nrow <- table_builder$nrow - n
  if(table_builder$nrow <= 0) stop("cursor_up beyond available cells")
  table_builder
}

#' Move cursor down
#'
#' Move table builder cursor down specified value (default 1)
#'
#' @param table_builder The table builder to work on
#' @param n units to move cursor down
#' @return a table builder with the cursor down n positions
#' @export
#'
#' @examples
#' library(magrittr)
#' x <- Parser$new()$run(y ~ x)
#' new_table_builder(x$right, x$left) %>% cursor_pos(3,3) %>% cursor_down(2)
#'
cursor_down <- function(table_builder, n=1)
{
  table_builder$nrow <- table_builder$nrow + n
  if(table_builder$nrow <= 0) stop("cursor_down beyond available cells")
  table_builder
}

#' Move cursor left
#'
#' Move table builder cursor left the specified value (default 1)
#'
#' @param table_builder The table builder to work on
#' @param n units to move cursor left
#' @return a table builder with the cursor left n positions
#' @export
#'
#' @examples
#' library(magrittr)
#' x <- Parser$new()$run(y ~ x)
#' new_table_builder(x$right, x$left) %>% cursor_pos(3,3) %>% cursor_left(2)
#'
cursor_left <- function(table_builder, n=1)
{
  table_builder$ncol <- table_builder$ncol - n
  if(table_builder$ncol <= 0) stop("cursor_left beyond available cells")
  table_builder
}

#' Move cursor right
#'
#' Move table builder cursor right the specified value (default 1)
#'
#' @param table_builder The table builder to work on
#' @param n units to move cursor right
#' @return a table builder with the cursor right n positions
#' @export
#'
#' @examples
#' library(magrittr)
#' x <- Parser$new()$run(y ~ x)
#' new_table_builder(x$right, x$left) %>% cursor_pos(3,3) %>% cursor_right(2)
#'
cursor_right <- function(table_builder, n=1)
{
  table_builder$ncol <- table_builder$ncol + n
  if(table_builder$ncol <= 0) stop("cursor_right beyond available cells")
  table_builder
}

#' Move cursor to position
#'
#' Move table builder cursor to the specified position
#'
#' @param table_builder The table builder to work on
#' @param nrow The number of the row to move too
#' @param ncol The number of the col to move too
#' @return a table builder with the cursor at the specified position
#' @export
#'
#' @examples
#' library(magrittr)
#' x <- Parser$new()$run(y ~ x)
#' new_table_builder(x$right, x$left) %>% cursor_pos(3,3)
#'
cursor_pos <- function(table_builder, nrow, ncol)
{
  if(nrow <= 0 || ncol <= 0) stop("cursor_pos does not allow negative values")
  table_builder$ncol <- ncol
  table_builder$nrow <- nrow
  table_builder
}

#' Move cursor to first column
#'
#' Move table builder cursor to the first column, does not advance row
#'
#' @param table_builder The table builder to work on
#' @return a table builder with the cursor at the first column
#' @export
#'
#' @examples
#' library(magrittr)
#' x <- Parser$new()$run(y ~ x)
#' new_table_builder(x$right, x$left) %>% cursor_pos(3,3) %>% carriage_return()
#'
carriage_return <- function(table_builder)
{
  table_builder$ncol <- 1
  table_builder
}

#' Move cursor to next line
#' Move table builder cursor to the next line (does not alter column)
#'
#' @param table_builder The table builder to work on
#' @param n optional number of line_feeds to perform
#' @return a table builder with the cursor at the first column
#' @export
#'
#' @examples
#' library(magrittr)
#' x <- Parser$new()$run(y ~ x)
#' new_table_builder(x$right, x$left) %>% cursor_pos(3,3) %>% line_feed()
#'
line_feed <- cursor_down

#' Return to 1st column, next line
#'
#' Return table_builder to 1st column, and advance to next line
#'
#' @param table_builder The table builder to work on
#' @return a table builder with the cursor at the first column on a new line
#' @export
#'
#' @examples
#' library(magrittr)
#' x <- Parser$new()$run(y ~ x)
#' new_table_builder(x$right, x$left) %>% new_line()
#'
new_line <- function(table_builder)
{
  table_builder     %>%
  carriage_return() %>%
  line_feed()
}

#' Open a new row
#'
#' Move table builder cursor to the bottom of all defined rows opening a new one
#' in the first column
#'
#' @param table_builder The table builder to work on
#' @return a table builder with the cursor at the first column
#' @export
#'
#' @examples
#' library(magrittr)
#' x <- Parser$new()$run(y ~ x)
#' new_table_builder(x$right, x$left) %>% new_row()
#'
new_row <- function(table_builder)
{
  table_builder %>%
  home()        %>%
  cursor_down(length(table_builder$table))
}

#' Open a new column in 1st row
#'
#' Advance table builder cursor to the furthest right column on the top row and open a new column
#'
#' @param table_builder The table builder to work on
#' @return a table builder with the cursor at the first column
#' @export
#'
#' @examples
#' library(magrittr)
#' x <- Parser$new()$run(y ~ x)
#' new_table_builder(x$right, x$left) %>% new_col()
#'
new_col <- function(table_builder)
{
  table_builder %>%
  home()        %>%
  cursor_right(length(table_builder$table[[1]]) )
}

#' Apply table building over variable
#'
#' Run a continuation function over a list of items.
#' Similar to a foldl in ML
#'
#' @param table_builder The table builder to work on
#' @param X list or vector of items to iterate
#' @param FUN the function to iterate over
#' @param ... additional arguments to pass to FUN
#' @return a table builder with the cursor at the last position of the apply
#' @export
#'
#' @examples
#' library(magrittr)
#' x <- Parser$new()$run(y ~ x)
#' new_table_builder(x$right, x$left) %>%
#' table_builder_apply(1:3, FUN=function(tb, x) {
#'   tb %>% write_cell(tg_N(x)) %>% cursor_right()
#' })
#'
table_builder_apply <- function(table_builder, X, FUN, ...)
{
  sapply(X, FUN=function(x) {
    table_builder <<- FUN(table_builder, x, ...)
  })
  table_builder
}

#' Add columns
#'
#' Add all elements specified and advance to the next column after each addition
#'
#' @param table_builder The table builder to work on
#' @param subrow optional additional specifier for sub element of AST row for traceabililty
#' @param subcol optional additional specifier for sub element of AST col for traceabililty
#' @param ... elements to add columnwise
#' @return a table builder with the cursor at the column past the last addition
#' @export
#'
#' @examples
#' library(magrittr)
#' x <- Parser$new()$run(y ~ x)
#' new_table_builder(x$right, x$left) %>%
#' add_col(tg_N(1:3))
add_col <- function(table_builder, ..., subrow=NA, subcol=NA)
{
  table_builder %>%
  table_builder_apply(args_flatten(...), FUN=function(tbl, object) {
    tbl %>%
    write_cell(object, subrow=subrow, subcol=subcol) %>%
    cursor_right()
  })
}

#' Add rows
#'
#' Add all elements specified and advance to the next row after each addition
#'
#' @param table_builder The table builder to work on
#' @param subrow optional additional specifier for sub element of AST row for traceabililty
#' @param subcol optional additional specifier for sub element of AST col for traceabililty
#' @param ... elements to add rowwise
#' @return a table builder with the cursor at the row past the last addition
#' @export
#'
#' @examples
#' library(magrittr)
#' x <- Parser$new()$run(y ~ x)
#' new_table_builder(x$right, x$left) %>%
#' add_row(tg_N(1:3))
add_row <- function(table_builder, ..., subrow=NA, subcol=NA)
{
  # Get flattened args list
  table_builder %>%
  table_builder_apply(args_flatten(...), FUN=function(tbl, object) {
    tbl %>%
    write_cell(object, subrow=subrow, subcol=subcol) %>%
    cursor_down()
  })
}

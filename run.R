#!/usr/local/bin/Rscript

task <- dyncli::main()

# load libraries
library(dyncli, warn.conflicts = FALSE)
library(dynwrap, warn.conflicts = FALSE)
library(dplyr, warn.conflicts = FALSE)
library(purrr, warn.conflicts = FALSE)
library(tibble, warn.conflicts = FALSE)
library(FateID, warn.conflicts = FALSE)

#####################################
###           LOAD DATA           ###
#####################################
expression <- task$expression
parameters <- task$parameters
priors <- task$priors

end_id <- priors$end_id
start_id <- priors$start_id
groups_id <- priors$groups_id

# TIMING: done with preproc
timings <- list(method_afterpreproc = Sys.time())

#####################################
###        INFER TRAJECTORY       ###
#####################################

# determine end groups
grouping <- groups_id$group_id %>% factor() %>% as.numeric() %>% set_names(groups_id$cell_id)
grouping <- grouping[rownames(expression)] # make sure order of cells is consistent
end_groups <- grouping[end_id] %>% unique()

# determine start group
start_group <- grouping[start_id %>% sample(1)] %>% unique()

# check if there are two or more end groups
if (length(end_groups) < 2) {
  msg <- paste0("FateID requires at least two end cell populations, but according to the prior information there are only ", length(end_groups), " end populations!")

  if (!identical(parameters$force, TRUE)) {
    stop(msg)
  }

  warning(msg, "\nForced to invent some end populations in order to at least generate a trajectory")
  poss_groups <- unique(grouping) %>% setdiff(start_group)
  if (length(poss_groups) == 1) {
    new_end_groups <- stats::kmeans(expression[grouping == poss_groups,], centers = 2)$cluster
    grouping[grouping == poss_groups] <- c(poss_groups, max(grouping) + 1)[new_end_groups]
    end_groups <- new_end_groups
  } else {
    end_groups <- sample(poss_groups, 2)
  }
}

# based on https://github.com/dgrun/FateID/blob/master/vignettes/FateID.Rmd
x <- as.data.frame(t(as.matrix(expression)))
y <- grouping
tar <- end_groups

# reclassify
if (parameters$reclassify) {
  rc <- reclassify(
    x,
    y,
    tar,
    clthr = parameters$clthr,
    nbfactor = parameters$nbfactor,
    q = parameters$q
  )
  y  <- rc$part
  x  <- rc$xf
}

# fate bias
fb <- fateBias(
  x,
  y,
  tar,
  z = NULL,
  minnr = parameters$minnr,
  minnrh = parameters$minnrh,
  nbfactor = parameters$nbfactor
)

# dimensionality reduction
dr  <- compdr(
  x,
  z = NULL,
  m = parameters$m,
  k = parameters$k
)

# principal curves
pr <- prcurve(
  y,
  fb,
  dr,
  k = parameters$k,
  m = parameters$m,
  trthr = parameters$trthr,
  start = start_group
)

# TIMING: done with trajectory inference
timings$method_aftermethod <- Sys.time()

#####################################
###     SAVE OUTPUT TRAJECTORY    ###
#####################################

# end_state_probabilities
end_state_probabilities <- fb$probs %>% as.data.frame() %>% rownames_to_column("cell_id")

# pseudotime
pseudotimes <-
  map2_dfr(names(pr$trc), pr$trc, function(curve_id, trc) {
    tibble(
      cell_id = trc,
      pseudotime = seq_along(trc)/length(trc),
      curve_id = curve_id
    )
  }) %>%
  arrange(pseudotime) %>%
  group_by(cell_id) %>%
  filter(pseudotime == max(pseudotime)) %>%
  filter(row_number() == 1) %>%
  ungroup()

pseudotimes <- pseudotimes %>% bind_rows(
  tibble(
    cell_id = setdiff(rownames(expression), pseudotimes$cell_id),
    pseudotime = 0
  )
)

# extract dimred
dimred <- dr[[1]][[1]] %>%
  as.matrix() %>%
  magrittr::set_rownames(rownames(expression)) %>%
  magrittr::set_colnames(., paste0("Comp", seq_len(ncol(.))))

output <-
  wrap_data(
    cell_ids = rownames(expression)
  ) %>%
  add_dimred(
    dimred = dimred
  ) %>%
  add_end_state_probabilities(
    pseudotime = pseudotimes,
    end_state_probabilities = end_state_probabilities
  ) %>%
  add_timings(
    timings = timings
  )

dyncli::write_output(output, task$output)


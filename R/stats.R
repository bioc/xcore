#' Combine p-values using Fisher method
#'
#' Fisher's method is a meta-analysis technique used to combine the results from
#' independent statistical tests with the same hypothesis
#' (\href{https://en.wikipedia.org/wiki/Fisher%27s_method}{Wikipedia article}).
#'
#' @inheritParams stats::pchisq
#' @param p.value a numeric vector of p-values to combine.
#'
#' @return a number giving combined p-value.
#'
#' @importFrom stats pchisq
#'
fisherMethod <- function(p.value, lower.tail = FALSE, log.p = TRUE) {
  stopifnot("p.value must be numeric" = is.numeric(p.value))
  stopifnot("p.value must be longer than 1" = length(p.value) > 1L)
  stopifnot("lower.tail must be TRUE or FALSE" = isTRUEorFALSE(lower.tail))
  stopifnot("log.p must be TRUE or FALSE" = isTRUEorFALSE(log.p))

  K <- 2 * length(p.value)
  X <- -2 * sum(log(p.value))
  cmbp <- stats::pchisq(X, df = K, lower.tail = lower.tail, log.p = log.p)

  return(cmbp)
}

#' Significance testing in linear ridge regression
#'
#' Standard error estimation and significance testing for coefficients
#' estimated in linear ridge regression. \code{ridgePvals} re-implement
#' original method by (Cule et al. BMC Bioinformatics 2011.) found in
#' \link[ridge]{ridge-package}. This function is intended to use with
#' \code{\link[glmnet]{cv.glmnet}} output.
#'
#' @param x input matrix, same as used in \code{\link[glmnet]{cv.glmnet}}.
#' @param y response variable, same as used in \code{\link[glmnet]{cv.glmnet}}.
#' @param beta matrix of coefficients, estimated using
#'   \code{\link[glmnet]{cv.glmnet}}.
#' @param lambda lambda value for which \code{beta} was estimated.
#' @param standardizex logical flag for x variable standardization, should be
#'   set to same value as \code{standarize} flag in \code{\link[glmnet]{cv.glmnet}}.
#' @param svdX optional singular-value decomposition of \code{x} matrix. One can
#'   be obtained using \code{link[base]{svd}}. Passing this argument omits
#'   internal call to \code{link[base]{svd}}, this is useful when calling
#'   \code{ridgePvals} repeatedly using same \code{x}.
#'
#' @return a data.frame with columns
#'   \describe{
#'     \item{coef}{\code{beta}'s names}
#'     \item{se}{\code{beta}'s standard errors}
#'     \item{tstat}{\code{beta}'s test statistic}
#'     \item{pval}{\code{beta}'s p-values}
#'   }
#'
ridgePvals <- function (x, y, beta, lambda, standardizex = TRUE, svdX = NULL) {
  n <- length(y)
  if (standardizex) x <- scale(x)
  if (is.null(svdX)) svdX <- svd(x)
  U <- svdX$u
  # D <- svdX$d # not used?
  D2 <- svdX$d ^ 2
  V <- svdX$v
  div <- D2 + lambda
  # estimate sig^2
  sig2hat <-                      # adding ( here helps a lot!    # t(U) %*% y; crossprod is way faster
    as.numeric(crossprod(y - U %*% (diag((D2) / (div)) %*% crossprod(U, y)))) /
    (n - sum(D2 * (D2 + 2 * lambda) / (div ^ 2)))
  varmat <- tcrossprod(V %*% diag(D2 / (div ^ 2)), V)
  varmat <- sig2hat * varmat
  se <- sqrt(diag(varmat))
  tstat <- abs(beta / se)
  pval <- 2 * (1 - stats::pnorm(tstat))

  res <-
    list(
      coef = beta,
      se = se,
      tstat = tstat,
      pval = pval)
  class(res) <- "data.frame"
  attr(res, "row.names") <- colnames(x)

  return(res)
}

#' Gene expression modeling pipeline
#'
#' \code{modelGeneExpression} uses parallelization if parallel backend is
#' registered. For that reason we advise against passing \code{parallel} argument
#' to internally called \code{\link[glmnet]{cv.glmnet}} routine.
#'
#' For speeding up the calculations consider lowering number of folds used in
#' internally run \code{\link[glmnet]{cv.glmnet}} by specifying \code{nfolds}
#' argument. By default 10 fold cross validation is used.
#'
#' The relationship between the expression (Y) and molecular signatures (X) is
#' described using linear model formulation. The pipeline attempts to model the
#' change in expression between basal expression level (u) and each sample, with
#' the goal of finding the unknown molecular signatures activities. Linear
#' models are fit using popular ridge regression implementation
#' \link[glmnet]{glmnet} (Friedman, Hastie, and Tibshirani 2010).
#'
#' If \code{pvalues} is set to \code{TRUE} the significance of the estimated
#' molecular signatures activities is tested using methodology introduced by
#' (Cule, Vineis, and De Iorio 2011) which original implementation can be found
#' in \link[ridge]{ridge-package}.
#'
#' If replicates are available the signatures activities estimates and
#' their standard error estimates can be combined. This is done by averaging
#' signatures activities estimates and pooling their significance estimates
#' using Stouffer's method for the Z-scores and Fisher's method for the p-values.
#'
#' For detailed pipeline description we refer interested user to paper
#' accompanying this package.
#'
#' @param mae MultiAssayExperiment object such as produced by
#'   \code{\link{prepareCountsForRegression}}.
#' @param yname string indicating experiment in \code{mae} to use as the
#'   expression input.
#' @param uname string indicating experiment in \code{mae} to use as the basal
#'   expression level.
#' @param xnames character indicating experiments in \code{mae} to use as
#'   molecular signatures.
#' @param design matrix giving the design matrix for the samples. Default
#'   (\code{NULL}) is to use design found in \code{mae} metadata. Columns
#'   corresponds to samples groups and rows to samples names. Only samples
#'   included in the design will be processed.
#' @param standardize logical flag indicating if the molecular signatures should
#'   be scaled. Advised to be set to \code{TRUE}.
#' @param parallel parallel argument to internally used
#'   \code{\link[glmnet]{cv.glmnet}} function. Advised to be set to \code{FALSE}
#'   as it might interfere with parallelization used in \code{modelGeneExpression}.
#' @param pvalues logical flag indicating if significance testing for the
#'   estimated molecular signatures activities should be performed.
#' @param precalcmodels optional list of precomputed \code{'cv.glmnet'} objects
#'   for each molecular signature and sample. The elements of this list should
#'   be matching the \code{xnames} vector. Each of those elements should be a
#'   named list holding \code{'cv.glmnet'} objects for each sample. If provided
#'   those models will be used instead of running regression from scratch.
#' @param ... arguments passed to glmnet::cv.glmnet.
#'
#' @return Nested list with following elements
#'   \describe{
#'     \item{regression_models}{Named list with elements corresponding to
#'       signatures specified in \code{xnames}. Each of these is a list holding
#'       \code{'cv.glmnet'} objects corresponding to each sample.}
#'     \item{pvalues}{Named list with elements corresponding to
#'       signatures specified in \code{xnames}. Each of these is a list holding
#'       \code{data.frame} of signature's p-values and test statistics
#'       estimated for each sample.}
#'     \item{zscore_avg}{Named list with elements corresponding to
#'       signatures specified in \code{xnames}. Each of these is a \code{matrix}
#'       holding replicate average Z-scores with columns corresponding to groups
#'       in the design.}
#'     \item{coef_avg}{Named list with elements corresponding to
#'       signatures specified in \code{xnames}. Each of these is a \code{matrix}
#'       holding replicate averaged signatures activities with columns
#'       corresponding to groups in the design.}
#'     \item{results}{Named list of a \code{data.frame}s holding replicate
#'       average molecular signatures, overall molecular signatures Z-score and
#'       p-values calculated over groups using Stouffer's and Fisher's methods.}
#'   }
#'
#' @examples
#' data("rinderpest_mini", "remap_mini")
#' base_lvl <- "00hr"
#' design <- matrix(
#'   data = c(1, 0, 0,
#'            1, 0, 0,
#'            1, 0, 0,
#'            0, 1, 0,
#'            0, 1, 0,
#'            0, 1, 0,
#'            0, 0, 1,
#'            0, 0, 1,
#'            0, 0, 1),
#'   ncol = 3,
#'   nrow = 9,
#'   byrow = TRUE,
#'   dimnames = list(colnames(rinderpest_mini), c("00hr", "12hr", "24hr")))
#' mae <- prepareCountsForRegression(
#'   counts = rinderpest_mini,
#'   design = design,
#'   base_lvl = base_lvl)
#' mae <- addSignatures(mae, remap = remap_mini)
#' mae <- filterSignatures(mae)
#' res <- modelGeneExpression(
#'   mae = mae,
#'   xnames = "remap",
#'   nfolds = 5)
#'
#' @importFrom foreach foreach %do% %dopar% %:%
#' @importFrom glmnet cv.glmnet
#' @importFrom methods is
#' @importFrom MultiAssayExperiment metadata
#' @importFrom iterators iter
#' @importFrom stats coef setNames var
#' @importFrom utils timestamp
#'
#' @export
modelGeneExpression <- function(mae,
                                yname = "Y",
                                uname = "U",
                                xnames,
                                design = NULL,
                                standardize = TRUE,
                                parallel = FALSE,
                                pvalues = TRUE,
                                precalcmodels = NULL,
                                ...) {
  stopifnot("mae must be an instance of class 'MultiAssayExperiment'" = is(mae, "MultiAssayExperiment"))
  stopifnot("yname must be a length one character" = is.character(yname) && length(yname) == 1)
  stopifnot("uname must be a length one character" = is.character(uname) && length(uname) == 1)
  stopifnot("yname must be distinct from uname" = yname != uname)
  stopifnot("xnames must be a character vector" = is.character(xnames))
  stopifnot("xnames must be distinct from yname and uname" = base::intersect(c(yname, uname), xnames) == 0)
  stopifnot("yname, uname and xnames must match mae names" = all(c(yname, uname, xnames) %in% names(mae)))
  zero_var_sig <- lapply(xnames, function(x) ! any(apply(mae[[x]], 2, var) == 0))
  names(zero_var_sig) <- paste0(xnames, " can not contain zero variance signatures")
  for (i in seq_along(zero_var_sig)) do.call(stopifnot, zero_var_sig[i])
  if (is.null(design)) { design <- MultiAssayExperiment::metadata(mae)[["design"]] }
  stopifnot("design must be a matrix" = is.matrix(design))
  stopifnot("design rownames must correspond to mae[[yname]] columns" = (! is.null(rownames(design))) && all(colnames(mae[[yname]]) %in% rownames(design)))
  stopifnot("each sample in design can be assigned only to one group" = all(rowSums(design) == 1 | rowSums(design) == 0))
  stopifnot("at least one sample in design must be assigned to a group" = sum(rowSums(design)) > 0)
  stopifnot("standardize must be TRUE or FALSE" = isTRUEorFALSE(standardize))
  stopifnot("parallel must be TRUE or FALSE" = isTRUEorFALSE(parallel))
  stopifnot("pvalues must be TRUE or FALSE" = isTRUEorFALSE(pvalues))
  if (! is.null(precalcmodels)) {
    stopifnot("precalcmodels must be a list" = is.list(precalcmodels))
    stopifnot("precalcmodels elements names must be included in xnames" = (! is.null(names(precalcmodels))) && all(names(precalcmodels) %in% xnames))
    stopifnot("precalcmodels must contain only objects of class 'cv.glmnet'" = all(vapply(X = unlist(precalcmodels, recursive = FALSE), FUN = is, FUN.VALUE = logical(1L), class2 = "cv.glmnet")))
    stopifnot("precalcmodels is not compatible with mae" =
                all(vapply(
                  X = names(precalcmodels),
                  FUN = function(xnm) {
                    all(vapply(
                      X = precalcmodels[[xnm]],
                      FUN = function(x) {
                        identical(rownames(x[["glmnet.fit"]][["beta"]]), colnames(mae[[xnm]]))
                      },
                      FUN.VALUE = logical(1L)
                    ))
                  },
                  FUN.VALUE = logical(1L)
                )))
  }

  groups <- design2factor(design)
  stopifnot("design try to use samples not included in mae[[yname]]" = all(names(groups) %in% colnames(mae[[yname]])))

  message("##------ modelGeneExpression: started ridge regression ", timestamp(prefix = "", quiet = TRUE))
  regression_models <-
    modelGeneExpression_ridge_regression_wraper(
      mae = mae,
      yname = yname,
      uname = uname,
      xnames = xnames,
      groups = groups,
      standardize = standardize,
      parallel = parallel,
      precalcmodels = precalcmodels,
      ...)
  message("##------ modelGeneExpression: finished ridge regression", timestamp(prefix = "", quiet = TRUE))

  if (pvalues) {
    message("##------ modelGeneExpression: started significance testing  ", timestamp(prefix = "", quiet = TRUE))
    pvalues <- modelGeneExpression_significance_testing_wraper(
      mae = mae,
      yname = yname,
      uname = uname,
      xnames = xnames,
      groups = groups,
      standardize = standardize,
      regression_models = regression_models)
    message("##------ modelGeneExpression: finished significance testing  ", timestamp(prefix = "", quiet = TRUE))
  }

  # gather results
  if (is.list(pvalues)) {
    zscore_avg <- lapply(pvalues, repVarianceWeightedAvgZscore, groups = groups)
    coef_avg <- lapply(X = xnames, function(xnm_) {
      getVarianceWeightedAvgCoeff(pvalues[[xnm_]], groups)
    })
    names(coef_avg) <- xnames
    results <- lapply(
      X = names(coef_avg),
      FUN = function(xnm_) {
        coef <- coef_avg[[xnm_]]
        x <- split(coef, col(coef, as.factor = TRUE))
        x <- c(list(name = rownames(coef)), x)

        # this block originate from older logic that generated results when pvalues == FALSE
        has_zscore <- ! is.null(zscore_avg)
        if (has_zscore && ncol(zscore_avg[[xnm_]]) > 1) {
          x[["z_score"]] <- apply(zscore_avg[[xnm_]], 1, stoufferZMethod)
        } else if (has_zscore && ncol(zscore_avg[[xnm_]]) == 1) {
          x[["z_score"]] <- zscore_avg[[xnm_]][, 1L, drop = TRUE]
        } else {
          x[["z_score"]] <- NA
        }

        class(x) <- "data.frame"
        attr(x, "row.names") <- seq_len(nrow(coef))
        if (length(zscore_avg)) {
          ord <- order(abs(x[["z_score"]]), decreasing = TRUE)
          x <- x[ord, ]
          rownames(x) <- NULL
        }
        x
      })
    names(results) <- names(coef_avg)
  } else {
    pvalues <- NULL
    zscore_avg <- NULL
    coef_avg <- NULL
    results <- NULL
  }

  return(list(
    regression_models = regression_models,
    pvalues = pvalues,
    zscore_avg = zscore_avg,
    coef_avg = coef_avg,
    results = results
  ))
}

# declare modelGeneExpression foreach variables
utils::globalVariables(c("x_", "xn_", "xnm_", "y_", "yn_", "id_"))

#' Ridge regression wrapper for modelGeneExpression
#'
#' Internal function used in \code{modelGeneExpression}. It runs ridge regression
#' parallelly across signatures and samples as specified by experiment design.
#'
#' @inheritParams modelGeneExpression
#' @param groups factor representation of design matrix.
#' @param ... arguments passed to glmnet::cv.glmnet.
#'
#' @return Named list with elements corresponding to signatures specified in
#'   \code{xnames}. Each of these is a list holding \code{'cv.glmnet'} objects
#'   corresponding to each sample.
#'
#' @importFrom foreach foreach %dopar% %:%
#' @importFrom iterators iter
#' @importFrom stats setNames
#'
modelGeneExpression_ridge_regression_wraper <- function(mae,
                                                        yname,
                                                        uname,
                                                        xnames,
                                                        groups,
                                                        standardize,
                                                        parallel,
                                                        precalcmodels,
                                                        ...) {
  iter_to_pass <- lapply(precalcmodels, names)

  args <- list(...)
  args[["offset"]] <- mae[[uname]]
  args[["alpha"]] <- 0
  args[["standardize"]] <- standardize
  args[["parallel"]] <- parallel

  regression_models <- foreach::foreach(
    x_ = iterators::iter(suppressWarnings(suppressMessages(mae[, , xnames]))),
    xn_ = xnames,
    .inorder = TRUE,
    .final = function(x) setNames(x, xnames)
  ) %:%
    foreach::foreach(
      y_ = iterators::iter(mae[[yname]][, names(groups), drop = FALSE]),
      yn_ = names(groups),
      .inorder = TRUE,
      .final = function(x) setNames(x, names(groups)),
      .packages = "glmnet"
    ) %dopar% {
      if (yn_ %in% iter_to_pass[[xn_]]) {
        res <- "precalc"
      } else {
        args[["x"]] <- quote(x_)
        args[["y"]] <- quote(y_)
        res <- do.call(glmnet::cv.glmnet, args)
      }

      return(res)
      rm(args, res); gc()
    }
  # add precalculated models
  for (xn in names(iter_to_pass)) {
    for (yn in iter_to_pass[[xn]])
      if (yn %in% names(groups)) {
        regression_models[[xn]][[yn]] <- precalcmodels[[xn]][[yn]]
      }
  }

  return(regression_models)
}

#' Statistical testing of ridge regression estimates wrapper for modelGeneExpression
#'
#' Internal function used in \code{modelGeneExpression}. It runs \code{ridgePvals}
#' parallelly across signatures and samples as specified by experiment design.
#'
#' @inheritParams modelGeneExpression
#' @param groups factor representation of design matrix.
#' @param regression_models Named list with elements corresponding to signatures
#'   specified in \code{xnames}. Each of these is a list holding
#'   \code{'cv.glmnet'} objects corresponding to each sample. Usually returned
#'   by \code{modelGeneExpression_ridge_regression_wraper}.
#'
#' @return Named list with elements corresponding to signatures specified in
#'   \code{xnames}. Each of these is a list holding \code{data.frame} of
#'   signature's p-values and test statistics estimated for each sample.
#'
#' @importFrom foreach foreach %dopar% %:%
#' @importFrom iterators iter
#' @importFrom stats coef setNames
#'
modelGeneExpression_significance_testing_wraper <- function(mae,
                                                            yname,
                                                            uname,
                                                            xnames,
                                                            groups,
                                                            standardize,
                                                            regression_models) {
  if (standardize) { # scale here to avoid scaling multiple times in ridgePvals
    for (xn in xnames) {
      mae[[xn]] <- scale(mae[[xn]])
    }
  }
  svdX <- foreach::foreach(
    x_ = iterators::iter(suppressWarnings(suppressMessages(mae[, , xnames]))),
    .inorder = TRUE,
    .final = function(x) setNames(x, xnames)
  ) %dopar% svd(x_)

  pvalues <- foreach::foreach(
    x_ = iterators::iter(suppressWarnings(suppressMessages(mae[, , xnames]))),
    xnm_ = xnames,
    .inorder = TRUE,
    .final = function(x) setNames(x, xnames)
  ) %:%
    foreach::foreach(
      y_ = iterators::iter(mae[[yname]][, names(groups), drop = FALSE]),
      id_ = names(groups),
      .inorder = TRUE,
      .final = function(x) setNames(x, names(groups)),
      .export = "ridgePvals"
    ) %dopar% {
      y_ <- y_ - mae[[uname]]
      lambda <- regression_models[[xnm_]][[id_]]$lambda.min
      beta <- coef(regression_models[[xnm_]][[id_]], s = lambda)
      beta <- beta[-1, ] # drop intercept
      ridgePvals(
        x = x_,
        y = y_,
        beta = beta,
        lambda = lambda,
        standardizex = FALSE,
        svdX = svdX[[xnm_]]
      )
    }

  return(pvalues)
}

# #' Calculate replicate averaged Z-scores
# #'
# #' Replicate averaged Z-scores is calculated by dividing replicate average
# #' coefficient by replicate pooled standard error.
# #'
# #' @param pvalues Data frame with \code{'se'} (standard error) and \code{'coef'}
# #'   (coefficient) columns. Such as in \code{pvalues} output of
# #'   \code{modelGeneExpression} .
# #' @param groups Factor giving group membership for samples in  \code{pvalues}.
# #'
# #' @return Numeric matrix of averaged Z-scores. Columns correspond to groups and
# #'   rows to predictors.
# #'
# repAvgZscore <- function(pvalues, groups) {
#   stopifnot("pvalues elements must be instances of class data.frame" = all(vapply(pvalues, function(x) is(x, "data.frame"), logical(1L))))
#   stopifnot("pavalues must have 'se' and 'coef' columns" = all(vapply(pvalues, function(p) all(c("se", "coef") %in% colnames(p)), logical(1L))))
#   stopifnot("groups must be a factor" = is.factor(groups))
#   stopifnot("groups length must equal pvalues length" = length(groups) == length(pvalues))
#   stopifnot("groups must not have unused levels" = setdiff(levels(groups), groups) == character(0))
#
#   se <- applyOverDFList(list_of_df = pvalues, col_name = "se", fun = poolSE, groups = groups)
#   estimate <- applyOverDFList(list_of_df = pvalues, col_name = "coef", fun = mean, groups = groups)
#   zscore <- estimate / se
#
#   return(zscore)
# }

#' Calculate replicate variance weighted averaged Z-scores
#'
#' Replicate averaged Z-scores is calculated by dividing replicate average
#' coefficient by replicate pooled standard error.
#'
#' @param pvalues Data frame with \code{'se'} (standard error) and \code{'coef'}
#'   (coefficient) columns. Such as in \code{pvalues} output of
#'   \code{modelGeneExpression} .
#' @param groups Factor giving group membership for samples in  \code{pvalues}.
#'
#' @return Numeric matrix of averaged Z-scores. Columns correspond to groups and
#'   rows to predictors.
#'
repVarianceWeightedAvgZscore <- function(pvalues, groups) {
  stopifnot("pvalues elements must be instances of class data.frame" = all(vapply(pvalues, function(x) is(x, "data.frame"), logical(1L))))
  stopifnot("pavalues must have 'se' and 'coef' columns" = all(vapply(pvalues, function(p) all(c("se", "coef") %in% colnames(p)), logical(1L))))
  stopifnot("groups must be a factor" = is.factor(groups))
  stopifnot("groups length must equal pvalues length" = length(groups) == length(pvalues))
  stopifnot("groups must not have unused levels" = setdiff(levels(groups), groups) == character(0))

  samples <- factor(names(groups))
  names(samples) <- names(groups)
  estimate <- applyOverDFList(list_of_df = pvalues, col_name = "coef", fun = function(x) x, groups = samples)
  variance_weights <- applyOverDFList(list_of_df = pvalues, col_name = "se", fun = function(x) 1 / x^2, groups = samples)
  weighted_mean <- foreach::foreach(gr_ = levels(groups), .combine = cbind) %dopar%
    {
      i <- groups == gr_
      wm <- rowSums(estimate[, i, drop = FALSE] * variance_weights[, i, drop = FALSE]) / rowSums(variance_weights[, i, drop = FALSE])
      matrix(
        data = wm, ncol = 1L, dimnames = list(names(wm), gr_)
      )
    }
  weighted_mean_se <- foreach::foreach(gr_ = levels(groups), .combine = cbind) %dopar%
    {
      i <- groups == gr_
      wmse <- sqrt(1 / rowSums(variance_weights[, i, drop = FALSE]))
      matrix(
        data = wmse, ncol = 1L, dimnames = list(names(wmse), gr_)
      )
    }
  weighted_z <- weighted_mean / weighted_mean_se

  return(weighted_z)
}

# #' Pool Standard Error / Standard Deviation
# #'
# #' Pooled standard error is calculated following (Cohen 1977) formulation for
# #' pooled standard deviation.
# #' TODO check out https://www.statisticshowto.com/find-pooled-sample-standard-error/, https://www.statisticshowto.com/pooled-standard-deviation/
# #'
# #' @param x Numeric vector of standard errors to pool.
# #'
# #' @return Number giving pooled standard error.
# #'
# poolSE <- function(x) {
#   sqrt(sum(x * x) / length(x))
# }

#' Combine Z-scores using Stouffer's method
#'
#' Stouffer's Z-score method is a meta-analysis technique used to combine the
#' results from independent statistical tests with the same hypothesis. It is
#' closely related to Fisher's method, but operates on Z-scores instead of
#' p-values
#' (\href{https://en.wikipedia.org/wiki/Fisher%27s_method}{Wikipedia article}).
#'
#' @param z a numeric vector of Z-score to combine.
#'
#' @return a number giving combined Z-score.
#'
#' @importFrom stats pchisq
#'
stoufferZMethod <- function(z) {
  z <- z[! is.na(z)]
  z_cmb <- sum(abs(z)) / sqrt(length(z))

  return(z_cmb)
}

# #' Calculate average coefficients matrix
# #'
# #' @param models list of \code{cv.glmnet} objects.
# #' @param group optional factor giving the grouping.
# #' @param lambda string indicating which lambda to use.
# #' @param drop_intercept logical indicating if intercept should be dropped from
# #'   the output.
# #'
# #' @return average coefficients matrix
# #'
# getAvgCoeff <- function(models, group = NULL, lambda = "lambda.min", drop_intercept = TRUE) {
#   coefs <- lapply(models, function(m) coef(m, s = m[[lambda]]))
#   if (drop_intercept) {
#     coefs <- lapply(coefs, function(m) {
#       keep <- grep(pattern = "(Intercept)", x = rownames(m), invert = TRUE)
#       m[keep, ]
#     })
#   }
#   coefs_avg <- lapply(X = levels(group), function(gr) {
#     mat <- do.call(cbind, coefs[group == gr])
#     if (ncol(mat) > 1) {
#       rowMeans(mat)
#     } else {
#       mat
#     }
#   })
#   coefs_avg <- do.call(cbind, coefs_avg)
#   colnames(coefs_avg) <- levels(group)
#
#   return(coefs_avg)
# }

#' Calculate variance weighted average coefficients matrix
#'
#' @param pvalues list of \code{data.frame}s outputs from \code{ridgePvals}.
#' @param groups factor giving the grouping.
#'
#' @return variance weighted average coefficients matrix
#'
getVarianceWeightedAvgCoeff <-
  function(pvalues,
           groups) {
    samples <- factor(names(groups))
    names(samples) <- names(groups)
    estimate <- applyOverDFList(list_of_df = pvalues, col_name = "coef", fun = function(x) x, groups = samples)
    variance_weights <- applyOverDFList(list_of_df = pvalues, col_name = "se", fun = function(x) 1 / x^2, groups = samples)
    weighted_mean <- foreach::foreach(gr_ = levels(groups), .combine = cbind) %dopar%
      {
        i <- groups == gr_
        wm <- rowSums(estimate[, i, drop = FALSE] * variance_weights[, i, drop = FALSE]) / rowSums(variance_weights[, i, drop = FALSE])
        matrix(
          data = wm, ncol = 1L, dimnames = list(names(wm), gr_)
        )
      }

    return(weighted_mean)
  }

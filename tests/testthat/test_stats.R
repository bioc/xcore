test_that("ridgePvals", {
  ridge_mod <- ridge::linearRidge(formula = mpg ~ .,
                                  data = mtcars,
                                  lambda = 2.747,
                                  scaling = "scale")
  ridge_pvals <- ridge::pvals(ridge_mod)
  xcore_pvals <- ridgePvals(x = scale(mtcars[, -1]),
                              y = mtcars[, 1] - mean(mtcars[, 1]), # ridge subtract avg from y
                              beta = ridge_mod$coef[, 1],
                              lambda = 2.747, standardizex = FALSE)
  testthat::expect_equal(
    round(as.numeric(ridge_pvals$se), 10),
    round(as.numeric(xcore_pvals$se), 10))
  testthat::expect_equal(
    round(as.numeric(ridge_pvals$tstat), 10),
    round(as.numeric(xcore_pvals$tstat), 10))
  testthat::expect_equal(
    round(as.numeric(ridge_pvals$pval), 10),
    round(as.numeric(xcore_pvals$pval), 10))
})

test_that("modelGeneExpression", {
  data("rinderpest_mini", "remap_mini")
  base_lvl <- "00hr"
  design <- matrix(
    data = c(1, 0,
             1, 0,
             1, 0,
             0, 1,
             0, 1,
             0, 1),
    ncol = 2,
    nrow = 6,
    byrow = TRUE,
    dimnames = list(c("00hr_rep1", "00hr_rep2", "00hr_rep3", "24hr_rep1", "24hr_rep2", "24hr_rep3"), c("00hr", "24hr"))
  )
  mae <- prepareCountsForRegression(
    counts = rinderpest_mini[, c("00hr_rep1", "00hr_rep2", "00hr_rep3", "24hr_rep1", "24hr_rep2", "24hr_rep3")],
    design = design,
    base_lvl = base_lvl)
  mae <- addSignatures(mae, remap = remap_mini)
  yname <- "Y"
  uname <- "U"
  xnames <- c("remap")

  testthat::expect_error(
    modelGeneExpression(
      mae = 1L
    ),
    "mae must be an instance of class 'MultiAssayExperiment'"
  )
  testthat::expect_error(
    modelGeneExpression(
      mae = mae,
      yname = LETTERS
    ),
    "yname must be a length one character"
  )
  testthat::expect_error(
    modelGeneExpression(
      mae = mae,
      yname = yname,
      uname = LETTERS
    ),
    "uname must be a length one character"
  )
  testthat::expect_error(
    modelGeneExpression(
      mae = mae,
      yname = yname,
      uname = yname
    ),
    "yname must be distinct from uname"
  )
  testthat::expect_error(
    modelGeneExpression(
      mae = mae,
      yname = yname,
      uname = uname,
      xnames = 1:3
    ),
    "xnames must be a character vector"
  )
  testthat::expect_error(
    modelGeneExpression(
      mae = mae,
      yname = yname,
      uname = uname,
      xnames = c(yname, uname)
    ),
    "xnames must be distinct from yname and uname"
  )
  testthat::expect_error(
    modelGeneExpression(
      mae = mae,
      yname = yname,
      uname = uname,
      xnames = letters
    ),
    "yname, uname and xnames must match mae names"
  )
  testthat::expect_error(
    modelGeneExpression(
      mae = mae,
      yname = yname,
      uname = uname,
      xnames = xnames
    ),
    "remap can not contain zero variance signatures"
  )
  mae <- filterSignatures(mae)
  testthat::expect_error(
    modelGeneExpression(
      mae = mae,
      yname = yname,
      uname = uname,
      xnames = xnames,
      design = LETTERS
    ),
    "design must be a matrix"
  )
  testthat::expect_error(
    modelGeneExpression(
      mae = mae,
      yname = yname,
      uname = uname,
      xnames = xnames,
      design = matrix(data = NA, dimnames = list("foo", "bar"))
    ),
    "design rownames must correspond to mae\\[\\[yname\\]\\] columns"
  )
  fake_design <- design + 1
  testthat::expect_error(
    modelGeneExpression(
      mae = mae,
      yname = yname,
      uname = uname,
      xnames = xnames,
      design = fake_design
    ),
    "each sample in design can be assigned only to one group"
  )
  fake_design <- fake_design - fake_design
  testthat::expect_error(
    modelGeneExpression(
      mae = mae,
      yname = yname,
      uname = uname,
      xnames = xnames,
      design = fake_design
    ),
    "at least one sample in design must be assigned to a group"
  )
  testthat::expect_error(
    modelGeneExpression(
      mae = mae,
      yname = yname,
      uname = uname,
      xnames = xnames,
      design = design,
      standardize = 1L
    ),
    "standardize must be TRUE or FALSE"
  )
  testthat::expect_error(
    modelGeneExpression(
      mae = mae,
      yname = yname,
      uname = uname,
      xnames = xnames,
      design = design,
      standardize = TRUE,
      parallel = 1L
    ),
    "parallel must be TRUE or FALSE"
  )
  testthat::expect_error(
    modelGeneExpression(
      mae = mae,
      yname = yname,
      uname = uname,
      xnames = xnames,
      design = design,
      standardize = TRUE,
      parallel = TRUE,
      pvalues = 1L
    ),
    "pvalues must be TRUE or FALSE"
  )
  testthat::expect_error(
    modelGeneExpression(
      mae = mae,
      yname = yname,
      uname = uname,
      xnames = xnames,
      design = design,
      standardize = TRUE,
      parallel = TRUE,
      elaborate_replicates_avg = TRUE,
      precalcmodels = LETTERS
    ),
    "precalcmodels must be a list"
  )
  testthat::expect_error(
    modelGeneExpression(
      mae = mae,
      yname = yname,
      uname = uname,
      xnames = xnames,
      design = design,
      standardize = TRUE,
      parallel = TRUE,
      elaborate_replicates_avg = TRUE,
      precalcmodels = list()
    ),
    "precalcmodels elements names must be included in xnames"
  )
  testthat::expect_error(
    modelGeneExpression(
      mae = mae,
      yname = yname,
      uname = uname,
      xnames = xnames,
      design = design,
      standardize = TRUE,
      parallel = TRUE,
      elaborate_replicates_avg = TRUE,
      precalcmodels = list(remap = list("foo"))
    ),
    "precalcmodels must contain only objects of class 'cv.glmnet'"
  )
  testthat::expect_error(
    modelGeneExpression(
      mae = mae,
      yname = yname,
      uname = uname,
      xnames = xnames,
      design = design,
      standardize = TRUE,
      parallel = TRUE,
      elaborate_replicates_avg = TRUE,
      precalcmodels = list(
        remap = list(
          bar = structure(
            list(glmnet.fit = list(beta = "bar")),
            class = "cv.glmnet")
          )
        )
    ),
    "precalcmodels is not compatible with mae"
  )
  testthat::expect_error(
    modelGeneExpression(
      mae = mae,
      yname = yname,
      uname = uname,
      xnames = xnames,
      design = design
    ),
    "design try to use samples not included in mae\\[\\[yname\\]\\]"
  )

  set.seed(1234512)
  res <- suppressWarnings(suppressMessages(modelGeneExpression(
    mae = mae,
    yname = yname,
    uname = uname,
    xnames = xnames)))
  testthat::expect_equal(is(res, "list"), TRUE)
  testthat::expect_equal(
    names(res),
    c("regression_models", "pvalues", "zscore_avg", "coef_avg", "results"))
  testthat::expect_equal(
    vapply(res$regression_models$remap, function(x) x[["lambda.min"]], numeric(1L)),
    c(`24hr_rep1` = 0.511733047560191, `24hr_rep2` = 0.519567836447116, `24hr_rep3` = 0.49538499285586)
  )
  testthat::expect_equal(
    head(res$results$remap, 5),
    structure(
      list(
        name = c(
          "GSE41561.E2F4.MCF-7_ICI",
          "GSE46055.KDM5B.SUM185_SHCTCF",
          "ENCSR218GSN.ZFX.HEK293T",
          "GSE110655.BAF155.VCaP_shARID1A",
          "ENCSR854MCV.IRF1.K-562"
        ),
        `24hr` = c(
          0.115110794546977, -0.10051401824911,
          -0.0738481337954334, -0.0708429108458732, 0.0609397756919803
        ),
        z_score = c(
          `GSE41561.E2F4.MCF-7_ICI` = 22.3161464203538,
          GSE46055.KDM5B.SUM185_SHCTCF = -14.5165271205966,
          ENCSR218GSN.ZFX.HEK293T = -13.6523986560216,
          GSE110655.BAF155.VCaP_shARID1A = -12.1878274397494,
          `ENCSR854MCV.IRF1.K-562` = 12.1721353732934
        )
      ),
      row.names = c(1L, 2L, 3L, 4L, 5L),
      class = "data.frame"
    )
  )

  # modelGeneExpression works with 1 replicate
  mae[["Y"]] <- mae[["Y"]][, 1, drop = FALSE]
  MultiAssayExperiment::metadata(mae)[["design"]] <-
    MultiAssayExperiment::metadata(mae)[["design"]][1:4,]
  res <- suppressWarnings(suppressMessages(modelGeneExpression(
    mae = mae,
    yname = yname,
    uname = uname,
    xnames = xnames)))

  testthat::expect_equal(is(res, "list"), TRUE)
  testthat::expect_equal(
    names(res),
    c("regression_models", "pvalues", "zscore_avg", "coef_avg", "results"))
  testthat::expect_equal(
    vapply(res$regression_models$remap, function(x) x[["lambda.min"]], numeric(1L)),
    c(`24hr_rep1` = 0.466272094050723)
  )
  testthat::expect_equal(
    head(res$results$remap, 5),
    structure(
      list(
        name = c(
          "GSE41561.E2F4.MCF-7_ICI",
          "GSE46055.KDM5B.SUM185_SHCTCF",
          "GSE110655.BAF155.VCaP_shARID1A",
          "ENCSR218GSN.ZFX.HEK293T",
          "ENCSR000BJR.NR3C1.A-549"
        ),
        `24hr` = c(
          0.120925741473048,
          -0.108759726505401,-0.0779421142937784,
          -0.0691510544420742,
          -0.0722428637001296
        ),
        z_score = c(
          `GSE41561.E2F4.MCF-7_ICI` = 13.470084029705,
          GSE46055.KDM5B.SUM185_SHCTCF = -9.02506582532614,
          GSE110655.BAF155.VCaP_shARID1A = -7.70459398771434,
          ENCSR218GSN.ZFX.HEK293T = -7.34541841134943,
          `ENCSR000BJR.NR3C1.A-549` = -7.29921519345464
        )
      ),
      row.names = c(1L, 2L, 3L, 4L, 5L),
      class = "data.frame"
    )
  )
})

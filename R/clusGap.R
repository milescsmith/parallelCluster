#### Originally from orphaned package SLmisc
#### (Version: 1.4.1, 2007-04-12, Maintainer: Matthias Kohl <kohl@sirs-lab.com>)
#### License: GPL (version 2 or later)
####
#### which said
####  "function corresponds to function gap in package SAGx"

## MM: SAGx is now in Bioconductor --- 1.10.1{devel} or 1.11.1{release}
##     had gap() *corrected* to re-cluster using FUNcluster --> see ./gap-SAGx.R.~orig~
##
## MM: Package 'lga' -- has gap() and lga and robust lga [-> UBC]
##    - it uses  boot() nicely  [2012-01: ORPHANED because  Justin Harrington is amiss]
## MM: renamed arguments, and changed almost everything

#' @title clusGap
#'
#' @description
#'
#' @param x
#' @param FUNcluster
#' @param K.max
#' @param B
#' @param d.power
#' @param spaceH0
#' @param verbose
#' @param parallel
#' @param plan plan for resolving parallel futures (e.g. how should certain parallel calculations be performed).
#' See \code{future::plan} for acceptable options.  Default: "multisession"
#' @param ...
#'
#' @importFrom rsvd rsvd
#' @importFrom FasterMatrixMath MatMult MatCross MatTCross
#' @importFrom matrixStats colMeans2
#' @importFrom future plan sequential
#' @importFrom furrr future_map furrr_options
#'
#' @return
#' @export
#'
#' @examples
clusGap <- function(
                    x,
                    FUNcluster,
                    K.max,
                    B = 100,
                    d.power = 1,
                    spaceH0 = c("scaledPCA", "original"),
                    verbose = interactive(),
                    parallel = FALSE,
                    future_plan = "multisession",
                    ...) {
  stopifnot(
    is.function(FUNcluster),
    length(dim(x)) == 2,
    K.max >= 2,
    (n <- nrow(x)) >= 1,
    ncol(x) >= 1
  )

  if (!is.integer(as.integer(B)) || as.integer(B) <= 0) {
    stop("'B' has to be a positive integer")
  }
  cl. <- match.call()

  if (isTRUE(parallel)) {
    plan(future_plan)
  } else {
    plan(sequential)
  }

  if (is.data.frame(x)) {
    x <- as.matrix(x)
  }

  W.k <- function(X, kk) {
    clus <- if (kk > 1) {
      FUNcluster(X, kk, ...)$cluster
    } else {
      rep.int(1L, nrow(X))
    }

    ##----------==-------- kmeans() has 'cluster'; pam() 'clustering'
    0.5 * sum(vapply(
      split(seq_len(n), clus),
      function(I) {
        xs <- X[I, , drop = FALSE]
        sum(dist(xs)^d.power / nrow(xs))
      }, 0.
    ))
  }

  if (verbose) {
    message("Clustering k = 1,2,..., K.max (= ", K.max, "): .. ", sep = "")
    }

  # for(k in 1:K.max)
  #     logW[k] <- log(W.k(x, k))
  logW <-
    unlist(
      future_map(
        .x = seq(1,K.max),
        .f = ~ log(W.k(x, .x)),
        .progress = TRUE,
        .options = furrr_options(seed = TRUE, scheduling = 1)
        )
      )

  if (verbose) {
    message("done\n")
  }

  spaceH0 <- match.arg(spaceH0)
  ## Scale 'x' into hypercube -- later fill with H0-generated data
  xs <-
    scale(
      x = x,
      center = TRUE,
      scale = FALSE
      )

  m.x <- rep(attr(xs, "scaled:center"), each = n) # for back-trafo later

  switch(
    EXPR = spaceH0,
    "scaledPCA" = {
      ## (These & (xs,m.x) above basically do stats:::prcomp.default()
      # V.sx <- svd(xs, nu = 0)$v
      V.sx <- -rsvd(xs, nv = min(dim(xs)), nu = 0)$v
      xs <- MatMult(A = xs, B = V.sx) # = transformed(x)
    },
    "original" = {}, # (do nothing, use 'xs')
    ## otherwise
    stop("invalid 'spaceH0':", spaceH0)
  )

  rng.x1 <- apply(xs, 2L, range)
  logWks <- matrix(0, B, K.max)

  if (verbose) {
    message("Bootstrapping, b = 1,2,..., B (= ", B,
      ")  [one \".\" per sample]:\n",
      sep = ""
    )
  }

  logWksList <- future_map(.x = seq(1,B), .f = \(b) {
    ## Generate "H0"-data as "parametric bootstrap sample" :
    z1 <- apply(rng.x1, 2,
      \(M, nn) {
        runif(nn, min = M[1], max = M[2])
        },
      nn = n
    )
    z <-
      switch(
        spaceH0,
        "scaledPCA" = MatTCross(z1, V.sx), # back transformed
        "original" = z1
      ) + m.x
    curLogWks <- unlist(lapply(seq(1,K.max), function(k) log(W.k(z, k))))
    if (verbose && !parallel) cat(".", if (b %% 50 == 0) paste(b, "\n"))
    curLogWks
    # for(k in 1:K.max) {
    #     logWks[b,k] <- log(W.k(z, k))
    # if(verbose) cat(".", if(b %% 50 == 0) paste(b,"\n"))
  }, .progress = TRUE, .options = furrr_options(seed = TRUE))

  logWks <-
    matrix(
      unlist(logWksList),
      byrow = TRUE,
      nrow = B
    )

  if (verbose && (B %% 50 != 0)) cat("", B, "\n")
  E.logW <- colMeans2(logWks)
  SE.sim <- sqrt((1 + 1 / B) * apply(logWks, 2, var))
  structure(
    class = "clusGap",
    list(
      Tab = cbind(logW, E.logW, gap = E.logW - logW, SE.sim),
      ## K.max == nrow(T)
      call = cl., spaceH0 = spaceH0,
      n = n, B = B, FUNcluster = FUNcluster
    )
  )
}

## lga/R/gap.R   --- has for Tibshirani et al (2001):
## ElogWks[k,] <- c(mean(BootOutput), sqrt(var(BootOutput)*(1+1/B)))
## GAP[k] <- ElogWks[k,1] - logWks[k]
## if (k > 1)
##     if(GAP[k-1] >= GAP[k]-ElogWks[k,2] & !doall)
##         finished <- TRUE
##  so they effectively only look for the *first* (local) maximum which ..
## MM: <==> diff(GAP) = GAP[k] - GAP[k-1] <= +SE.sim[k]


## criteria.DandF() -- Dudoit and Fridlyand (2002)
## ---------------- looks at the *global* maximum and then to the left..
## y <- x$data
## crit <- diff(y[which.max(y[,"Gap"]), c("Sks", "Gap")])
## nclust <- min(which(y[,"Gap"] > crit))
## return(ifelse(nclust == nrow(y), NA, nclust))

maxSE <- function(
                  f,
                  SE.f,
                  method = c(
                    "firstSEmax", "Tibs2001SEmax",
                    "globalSEmax", "firstmax", "globalmax"
                  ),
                  SE.factor = 1) {

  method <- match.arg(method)

  stopifnot(
    (K <- length(f)) >= 1,
    K == length(SE.f),
    SE.f >= 0,
    SE.factor >= 0
    )

  fSE <- SE.factor * SE.f
  switch(method,
    "firstmax" = { ## the first local maximum  (== firstSEmax with SE.factor == 0)
      decr <- diff(f) <= 0 # length K-1
      if (any(decr)) {
        which.max(decr)
      } else {
        K
      } # the first TRUE, or K
    },
    "globalmax" = {
      which.max(f)
    },
    "Tibs2001SEmax" = { ## The one Tibshirani et al (2001) proposed:
      ## "the smallest k such that f(k) >= f(k+1) - s_{k+1}"
      g.s <- f - fSE
      if (any(mp <- f[-K] >= g.s[-1])) {
        which.max(mp)
      } else {
        K
      }
    },
    "firstSEmax" = { ## M.Maechler(2012): rather ..
      ## look at the first *local* maximum and then to the left ..:
      decr <- diff(f) <= 0 # length K-1
      nc <- if (any(decr)) which.max(decr) else K # the first TRUE, or K
      if (any(mp <- f[seq_len(nc - 1)] >= f[nc] - fSE[nc])) {
        which(mp)[1]
      } else {
        nc
      }
    },
    "globalSEmax" = { ## Dudoit and Fridlyand (2002) *thought* Tibshirani proposed..
      ## in 'lga', see criteria.DandF():
      ## looks at the *global* maximum and then to the left..
      nc <- which.max(f)
      if (any(mp <- f[seq_len(nc - 1)] >= f[nc] - fSE[nc])) {
        which(mp)[1]
      } else {
        nc
      }
    }
  )
}

print.clusGap <- function(x, method = "firstSEmax", SE.factor = 1, ...) {
  method <- match.arg(method, choices = eval(formals(maxSE)$method))
  stopifnot((K <- nrow(T <- x$Tab)) >= 1, SE.factor >= 0)
  cat("Clustering Gap statistic [\"clusGap\"] from call:\n", deparse(x$call),
    sprintf(
      "\nB=%d simulated reference sets, k = 1..%d; spaceH0=\"%s\"\n",
      x$B, K, x$spaceH0
    ),
    sep = ""
  )
  nc <- maxSE(
    f = T[, "gap"], SE.f = T[, "SE.sim"],
    method = method, SE.factor = SE.factor
  )
  cat(
    sprintf(
      " --> Number of clusters (method '%s'%s): %d\n",
      method, if (grepl("SE", method)) {
        sprintf(", SE.factor=%g", SE.factor)
      } else {
        ""
      }, nc
    )
  )
  print(T, ...)
  invisible(x)
}

plot.clusGap <- function(
  x,
  type = "b",
  xlab = "k",
  ylab = expression(Gap[k]),
  main = NULL,
  do.arrows = TRUE,
  arrowArgs = list(col = "red3", length = 1 / 16, angle = 90, code = 3),
  ...
) {
  stopifnot(is.matrix(Tab <- x$Tab), is.numeric(Tab))
  K <- nrow(Tab)
  k <- seq_len(K) # == 1,2,... k
  if (is.null(main)) {
    main <- paste(strwrap(deparse(x$call, 150)[1], width = 60, exdent = 7),
      collapse = "\n"
    )
  }
  gap <- Tab[, "gap"]
  plot(k, gap, type = type, xlab = xlab, ylab = ylab, main = main, ...)
  if (do.arrows) {
    do.call(
      arrows,
      c(list(k, gap + Tab[, "SE.sim"], k, gap - Tab[, "SE.sim"]), arrowArgs)
    )
  }
  invisible()
}

#' Calculates distance covariance and distance correlation matrices
#'
#' @param X A dataframe or matrix with n rows and p columns.
#' @param Y Either NULL or a dataframe or a matrix with n rows and q columns. If only X is provided, distance covariances/correlations are calculated between all groups in X. If X and Y are provided, distance covariances/correlations are calculated between all groups in X and all groups and Y.
#' @param calc.dcov Should distance covariance matrix be calculated?
#' @param calc.dcor Should distance correlation matrix be calculated? 
#' @param calc.cor If set as "pearson", "spearman" or "kendall", a corresponding correlation matrix is addionally calculated.
#' @param calc.pval.cor IF TRUE, a p-value based on the Pearson or Spearman correlation matrix is calculated (not implemented for calc.cor ="kendall") using Hmisc::rcorr
#' @param return.data IF TRUE, X and Y are contained in the resulting dcmatrix object.
#' @param test specifies the type of test that is performed, "permutation" performs a Monte Carlo Permutation test. "gamma" performs a test based on a gamma approximation of the test statistic under the null. "conservative" performs a conservative two-moment approximation. "bb3" performs a quite precise three-moment approximation and is recommended when computation time is not an issue.
#' @param adjustp If setting this parameter to "holm", "hochberg", "hommel", "bonferroni", "BH", "BY" or "fdr", corresponding adjusted p-values are returned.
#' @param b specifies the number of random permutations used for the permutation test. Ignored when test="gamma"
#' @param affine logical; indicates if the affinely transformed distance covariance should be calculated or not.
#' @param bias.corr logical; indicates if the bias corrected version of the sample distance covariance should be calculated
#' @param group.X A vector of length p, each entry specifying the group membership of the respective column in X. Each group is handled as one sample for calculating the distance covariance/correlation matrices. If NULL, every sample is handled as an individual group.
#' @param group.Y A vector of length q, each entry specifying the group membership of the respective column in Y. Each group is handled as one sample for calculating the distance covariance/correlation matrices. If NULL, every sample is handled as an individual group.
#' @param metr.X Either a single metric or a list providing a metric for each group in X.
#' @param metr.Y see metr.X.
#' @param use : "all" uses all observations, "complete.obs" excludes NA's, "pairwise.complete.obs" uses pairwise complete observations for each comparison.
#' @param algorithm: One of "auto", "fast", "memsave" and "standard". "memsave" is typically very inefficient for dcmatrix and should only be applied in exceptional cases.
#' @param fc.discrete: If TRUE, "discrete" metric is applied automatically on samples corresponding to a single column of type "factor" or "character".
#' @return dcmatrix object
#' @export

dcmatrix <- function (X,
                      Y = NULL,
                      calc.dcov = TRUE,
                      calc.dcor = TRUE,
                      calc.cor = "pearson",
                      calc.pval.cor = FALSE,
                      return.data = TRUE,
                      test = "none",
                      adjustp = "none",
                      b = 499,
                      affine = FALSE,
                      bias.corr = TRUE,
                      group.X = NULL,
                      group.Y = NULL,
                      metr.X = "euclidean",
                      metr.Y = "euclidean",
                      use="everything",
                      algorithm ="auto",
                      fc.discrete = FALSE) {
  
  ## Checks
  
  output <- list()
  output$call <- match.call()
  
  if(return.data) {
    output$X <- X
    output$Y <- Y
  } else {
    output <- NULL
  }
  
  
  withY <- ifelse(is.null(Y), FALSE, TRUE)
 
  
  dogamma <- docons <- dobb3 <- doperm <- donotest <- FALSE
  
  if (test == "none")
    donotest <- TRUE 
  else if (test == "gamma")
    dogamma <- TRUE 
  else if (test == "conservative")
    docons <- TRUE
  else if (test == "bb3")
    dobb3 <- TRUE
  else if (test == "permutation")
    doperm <- TRUE
  else
    stop ("Test must be one of \"none\", \"permutation\", \"gamma\", \"bb3\" or \"conservative\"")
  
  
  use.all <- use.pw <- FALSE
  
  if (use == "complete.obs") {
    cc <- which(complete.cases(X))
    if (withY) {
      cc <- intersect(cc,which(complete.cases(Y)))
      Y <- Y[cc,]
    }
    X <- X[cc,]
    use.all <- TRUE
  } else if (use == "everything") {
    use.all <- TRUE
  } else if (use == "pairwise.complete.obs") {
    use.pw <- TRUE
  } else {
    stop("use must be one of \"everything\", \"complete.obs\" or \"pairwise.complete.obs\"")
  }
  

  
  
  if (is.vector(X)) {
    X <- as.matrix(X)
  }
  
  p <- ncol(X)
  n <- nrow(X)
  
  if (is.null(group.X)) {
    group.X <- 1:p
  }
  
  tblX <- table(group.X)
  labelsX <- as.factor(names(tblX))
  pX <- as.numeric(tblX)
  dX <- dY <- length(pX)
  ms.grpX <- ms.grpY <- NULL
  grouplistsX <- lapply(1:dX, function(t) which(group.X == labelsX[t]))
  prepX <- as.list(rep(NA,dX))
  dvarX <- rep(NA,dX)
  
  lmX <- length(metr.X)
  if (lmX ==1) {
    metr.X <- as.list(replicate(dX, metr.X))
  } else if (lmX == 2) {
    ischar <- suppressWarnings(is.na(as.numeric(metr.X[2])))
    if (!ischar)
      metr.X <- lapply(1:dX, function(u) metr.X)
  }
  
  if (is.character(metr.X) & lmX == dX) {
    ischar <- suppressWarnings(is.na(as.numeric(metr.X[2])))
    if (ischar)
      metr.X <- as.list(metr.X)
  }
  
  if (use.all) {
    ms.X <- sapply(1:dX, function(t) any(!complete.cases(X[,t])))
    ms.grpX <- which(ms.X)
  } else {
    ms.X <- rep(FALSE,dX)
    ms.grpX <- numeric(0)
  }
  
  ## normalize samples if calculation of affinely invariant distance covariance is desired
  if (affine) {
    for (j in 1 : dX) {
      if (use.all) {
        X[,grouplistsX[[j]]] <- normalize.sample(X[,grouplistsX[[j]]], n, pX[j])
      } else {
        cc <- complete.cases(X[,grouplistsX[[j]]])
        ncc <- length(cc)
        X[cc,grouplistsX[[j]]] <- normalize.sample(X[cc,grouplistsX[[j]]], n, pX[j])
      }
    }
  }
  

  
  if (withY) {
    
    lmY <- length(metr.Y)
   
    
    if (is.vector(Y)) {
      Y <- as.matrix(Y)
    }
    
    q <- ncol(Y)
    m <- nrow(Y)
   
     if (is.null(group.Y)) {
      group.Y <- 1 : q
    }
    
    tblY <- table(group.Y)
    labelsY <- as.factor(names(tblY))
    pY <- as.numeric(tblY)
    dY <- length(pY)
    grouplistsY <- lapply(1:dY, function(t) which(group.Y == labelsY[t]))
    prepY <- as.list(rep(NA,dY))
    dvarY <- rep(NA,dY)
    if (use.all) {
      ms.Y <- sapply(1:dY, function(t) any(!complete.cases(Y[,t])))
      ms.grpY <- which(sapply(1:dY, function(t) any(!complete.cases(Y[,t]))))
    } else {
      ms.Y <- rep(FALSE,dY)
      ms.grpY <- numeric(0)
    }
    
    if (lmY ==1) {
      metr.Y <- as.list(replicate(dY, metr.Y))
    } else if (lmX == 2) {
      ischar <- suppressWarnings(is.na(as.numeric(metr.Y[2])))
      if (!ischar)
        metr.Y <- lapply(1:dY, function(u) metr.Y)
    }
    
    if (is.character(metr.Y) & lmY == dY) {
      ischar <- suppressWarnings(is.na(as.numeric(metr.Y[2])))
      if (ischar)
        metr.Y <- as.list(metr.Y)
    }
   
     if (m != n) 
      stop("X and Y must have same number of rows (samples)")
    
    if (affine) {
      for (j in 1 : dY) {
        if (use.all) {
          Y[,grouplistsY[[j]]] <- normalize.sample(Y[,grouplistsY[[j]]], n, pY[j])
        } else {
          cc <- complete.cases(Y[,grouplistsY[[j]]])
          ncc <- length(cc)
          Y[cc,grouplistsX[[j]]] <- normalize.sample(Y[cc,grouplistsX[[j]]], ncc, pY[j])
        }
      }
    }
 
  }
  

  
  
  if (algorithm == "auto") {
    gofast <- (p == length(group.X)) * (n>200) & (!dobb3) * all(metr.X %in% c("euclidean", "discrete"))
    if (withY) 
      gofast <- gofast * (q == length(group.Y)) * all(metr.Y %in% c("euclidean", "discrete"))
    if (gofast) {
      algorithm <- "fast"
    } else {
      algorithm <- "standard"
    }
  }
  
  alg.fast <- alg.standard <- alg.memsave <- FALSE
  
  if (algorithm == "fast") {
    alg.fast <- TRUE 
    if (doperm) 
      terms.smp <- function(terms, smp) {sampleterms.fast.matr(terms, smp)}
    } else if (algorithm == "standard") {
    alg.standard <- TRUE
    if (doperm) 
      terms.smp <- function(terms, smp, ndisc = NULL) {sampleterms.standard(terms, smp)}
    }  else if (algorithm == "memsave") {
    alg.memsave <- TRUE
    if (doperm) 
      terms.smp <- function(terms, smp, ndisc = NULL) {sampleterms.memsave(terms, smp)}
  } 
  else
    stop ("Algorithm must be one of \"fast\", \"standard\", \"memsave\" or \"auto\"")
  
  
  if (!alg.standard & dobb3) 
    stop("bb3 p-value calculation is only possible with algorithm=standard!")
  
  
  if (bias.corr == TRUE) {
    termstodcov2 <- function(aijbij,Sab,Tab,n) {
      aijbij/ n / (n - 3) - 2 * Sab / n / (n - 2) / (n - 3) + Tab / n / (n - 1) / (n - 2) / (n - 3) 
    }
    dcov2todcov <- function(dcov2) {
      sqrt(abs(dcov2)) * sign(dcov2)
    }
    dcov2todcor <- function(dcov2, dvarX, dvarY) {
      (sqrt(abs(dcov2)) * sign(dcov2)) / sqrt(sqrt(dvarX * dvarY))
    }
  } else  {
    termstodcov2 <- function(aijbij, Sab, Tab, n) {
      aijbij / n / n - 2 * Sab / n / n / n + Tab / n / n / n / n
    }
    dcov2todcov <- function(dcov2) {
      sqrt(dcov2)
    }
    dcov2todcor <- function(dcov2, dvarX, dvarY) {
      sqrt(dcov2) / sqrt(sqrt(dvarX * dvarY))
    }
  }
  
  if (dogamma) {
    testfunc <- function(terms, ...) {
      n <- terms$ncc
      Saa <- vector_prod_sum(terms$aidot,terms$aidot)
      Sbb <- vector_prod_sum(terms$bidot,terms$bidot)
      Sab <- vector_prod_sum(terms$aidot,terms$bidot)
      dvarX <- terms$aijaij / n / (n - 3) - 2 * Saa/ n / (n - 2) / (n - 3) + terms$adotdot * terms$adotdot / n / (n - 1) / (n - 2) / (n - 3) 
      dvarY <- terms$bijbij / n / (n - 3) - 2 * Sbb / n / (n - 2) / (n - 3) + terms$bdotdot * terms$bdotdot / n / (n - 1) / (n - 2) / (n - 3) 
      dcov2 <- terms$aijbij / n / (n - 3) - 2 * Sab / n / (n - 2) / (n - 3) + terms$adotdot * terms$bdotdot / n / (n - 1) / (n - 2) / (n - 3) 
      U1 <- dvarX  * dvarY
      U2 <- terms$adotdot / n / (n - 1)
      U3 <- terms$bdotdot / n / (n - 1)
      alph <- 1 / 2 * (U2 ^ 2 * U3 ^ 2) / U1
      beta <- 1 / 2 * (U2 * U3) / U1
      stat <- n *  dcov2 + U2 * U3
      pval <- pgamma(stat, alph, beta, lower.tail = FALSE) 
      return(pval)
    }
  } else if (doperm) {
    testfunc <- function(dcov2, smp, terms, ...) {
      n <- terms$ncc
      if (is.na(dcov2))
        return(NA)
      Tab <- terms$adotdot * terms$bdotdot
      reps <- lapply(1:b, function(t) {
        terms.sample <- terms.smp(terms,smp[[t]])
        return(termstodcov2(terms.sample$aijbij, terms.sample$Sab, Tab, n))
      })
      pval <- (1 + length(which(reps > dcov2))) / (1 + b)
      return(pval)
    }
  } else if (docons) {
    testfunc <- function(terms, moms.X, moms.Y,...) {
      n <- terms$ncc
      est.m2 <- sum((moms.X * moms.Y)) / n ^ 10
      est.m1 <- terms$adotdot * terms$bdotdot / n ^ 3 / (n - 1)
      est.var <- (est.m2 - est.m1 ^ 2)
      alpha <- sqrt(est.var / 2 / est.m1 ^ 2)
      stat <- terms$aijbij / n - 2 * vector_prod_sum(terms$aidot,terms$bidot) / n ^ 2 + terms$adotdot * terms$bdotdot / n ^ 3
      pval <- pchisq(stat * sqrt(2) / sqrt(est.var), df = 1 / alpha, lower.tail = FALSE)  
      return(pval)
    }
  } 
  else if (dobb3) {
    testfunc <- function(terms, moms.X, moms.Y,...) {
      n <- terms$ncc
      est.m2 <- sum((moms.X$vc * moms.Y$vc)) / n ^ 10
      est.m1 <- terms$adotdot * terms$bdotdot / n ^ 3 / (n - 1)
      est.var <- (est.m2 - est.m1 ^ 2)
      est.skw <- moms.X$skw * moms.Y$skw
      beta <- est.skw / sqrt(8)
      stat <- terms$aijbij / n - 2 * vector_prod_sum(terms$aidot,terms$bidot) / n ^ 2 + terms$adotdot * terms$bdotdot / n ^ 3
      centstat <- (stat - est.m1) /  sqrt(est.var)
      pval <- pchisq((centstat * sqrt(2) + 1 / beta) / beta , df = 1 / beta ^ 2, lower.tail = FALSE)  
      return(pval)
    } 
  } else if (donotest) {
    testfunc <- function(...) {}
  }
  
  if (!calc.dcov) {
    dcov2todcov <- function(...) {}
  }
  
  if (!calc.dcor) {
    dcov2todcor <- function(...) {}
  }
  
  if (doperm & use.all) {
    perms <- lapply(1:b, function(t) sample(1:n))
  } else {
    perms <- NULL
  }
  
  extendoutput <- doperm| ((dobb3|docons)*use.pw)
  

  
  if (fc.discrete) {
    for (j in 1:dX) {
      if (is.factor(X[,grouplistsX[[j]]]))
        metr.X[[j]] <- "discrete"
    }
    if (withY) {
      for (j in 1:dY) {
        if (is.factor(Y[,grouplistsY[[j]]]))
          metr.Y[[j]] <- "discrete"
      }
    }
  }
  
  
  
  if (calc.cor %in% c("spearman","kendall", "pearson")) {
    output$corr <- cor(X,Y, use = use, method = calc.cor)
    if (calc.pval.cor) {
      if (calc.cor %in% c("spearman", "pearson")) {
        if (!withY) {
          corrp <- Hmisc::rcorr(X, type = calc.cor)
          output$pval.cor <- corrp$P
          diag(output$pval.cor) <- 0
           if (use.all)
            output$pval.cor[which(corrp$n<n,arr.ind=TRUE)] <- NA
       } else {
          corrp <- Hmisc::rcorr(X,Y)
          output$pval.cor <- corrp$P[1:dX,(dX+1):(dX+dY)]
          if (use.all)
            output$pval.cor[which(corrp$n[1:dX,(dX+1):(dX+dY)]<n,arr.ind=TRUE)] <- NA
       }  
      } else 
        warning("P-Value calculation for Kendall correlation not implemented")
    }
  }
  
  
  
  if (alg.fast) {
    discrete.X <- (metr.X == "discrete")
    if (withY)
      discrete.Y <- (metr.Y == "discrete")
  }
  
  
 
  if (calc.dcov)
    output$dcov <- matrix(nrow = dX, ncol = dY)
  
  if (calc.dcor) {
    output$dcor <- matrix(nrow = dX, ncol = dY)
    if (!withY)
      diag(output$dcor) <- 1
  }
  
  if (!donotest) {
    output$pvalue <- matrix(nrow = dX, ncol = dY)
    if (!withY)
      diag(output$pvalue) <- 0
  }
  
  momsX <- momsY <- NULL
  
  if ((docons | dobb3) & !use.pw) {
    momsX <- as.list(rep(NA,dX))
    if (withY)
      momsY <- as.list(rep(NA,dY))
  }
  
  
  for (j in setdiff(1:dX,ms.grpX)) {
    if (alg.fast) {
      prepX[[j]] <- prep.fast(X[,j], n, discrete = discrete.X[j], pairwise = use.pw)
    } else if (alg.memsave) {
      prepX[[j]] <- prep.memsave(X[,grouplistsX[[j]]], n, pX[j],  metr.X = metr.X[[j]], pairwise = use.pw)
    } else if (alg.standard) {
      prepX[[j]] <- prep.standard(X[,grouplistsX[[j]]], n, pX[j],  metr.X = metr.X[[j]], pairwise = use.pw)
    }  
    
    Saa <- vector_prod_sum(prepX[[j]]$aidot,prepX[[j]]$aidot)
    
    if ((docons | dobb3) & !use.pw) {
      momsX[[j]] <- calcmom(aijaij = prepX[[j]]$aijaij, Saa = Saa, adotdot = prepX[[j]]$adotdot, aidot = prepX[[j]]$aidot, distX = prepX[[j]]$distX, n = n, dobb3 = dobb3)
    }
    dvarX[j] <- termstodcov2(prepX[[j]]$aijaij, Saa, prepX[[j]]$adotdot*prepX[[j]]$adotdot, prepX[[j]]$ncc) 
  }
  
  if (!withY & calc.dcov) 
    diag(output$dcov) <- sqrt(dvarX)
  
  
  if (withY) {
    for (j in setdiff(1:dY,ms.grpY)) {
      if (alg.fast) {
        prepY[[j]] <- prep.fast(Y[,j], n, discrete = discrete.Y[j], pairwise = use.pw)
      } else if (alg.memsave) {
        prepY[[j]] <- prep.memsave(Y[,grouplistsY[[j]]], n, pY[j], metr.X = metr.Y[[j]], pairwise = use.pw)
      } else if (alg.standard) {
        prepY[[j]] <- prep.standard(Y[,grouplistsY[[j]]], n, pY[j], metr.X = metr.Y[[j]], pairwise = use.pw)
      }  
      Sbb <- vector_prod_sum(prepY[[j]]$aidot, prepY[[j]]$aidot)
      
      if ((docons | dobb3) & !use.pw) {
        momsY[[j]] <- calcmom(aijaij = prepY[[j]]$aijaij, Saa = Sbb, adotdot = prepY[[j]]$adotdot, aidot = prepY[[j]]$aidot, distX = prepY[[j]]$distX, n = n, dobb3 = dobb3)
      }
      dvarY[j] <- termstodcov2(prepY[[j]]$aijaij, Sbb, prepY[[j]]$adotdot*prepY[[j]]$adotdot, prepY[[j]]$ncc) 
    }
  }
  

  if (!withY) {
    if (dX > 1) {
      for (i in setdiff(1:(dX-1),ms.grpX)) {
        for (j in setdiff((i+1):dX,ms.grpX)) {
          if (alg.fast) {
            terms <- preptoterms.fast(prepX[[i]], prepX[[j]], n, pairwise = use.pw, discrete.X[[i]], discrete.X[[j]], perm = extendoutput)
          } else if (alg.memsave) {
            terms <- preptoterms.memsave(prepX[[i]], prepX[[j]], metr.X[[i]], metr.X[[j]], n, pairwise = use.pw, perm = extendoutput) 
          } else if (alg.standard) {
            terms <- preptoterms.standard(prepX[[i]], prepX[[j]], n, pairwise = use.pw, perm = extendoutput)
          }  
          dcov2XY <- termstodcov2(terms$aijbij, vector_prod_sum(terms$aidot, terms$bidot), terms$adotdot * terms$bdotdot, terms$ncc)
          output$dcov[i,j] <- output$dcov[j,i] <- dcov2todcov(dcov2 = dcov2XY)
          if (use.pw) {
            Saa <- vector_prod_sum(terms$aidot, terms$aidot)
            Sbb <- vector_prod_sum(terms$bidot, terms$bidot)
            dvX <-  termstodcov2(terms$aijaij, Saa, terms$adotdot * terms$adotdot, terms$ncc)
            dvY <-  termstodcov2(terms$bijbij, Sbb, terms$bdotdot * terms$bdotdot, terms$ncc)
            if (docons | dobb3) {
              moms.X <- calcmom(aijaij = terms$aijaij, Saa = Saa, adotdot = terms$adotdot, distX = terms$distX, n = terms$ncc, aidot = terms$aidot, dobb3 = dobb3)
              moms.Y <- calcmom(aijaij = terms$bijbij, Saa = Sbb, adotdot = terms$bdotdot, distX = terms$distY, n = terms$ncc, aidot = terms$bidot, dobb3 = dobb3)
            }
            if (doperm) {
              perms <- lapply(1:b, function(t) sample(1:terms$ncc))
            }
            
          } else {
            dvX <- dvarX[i]
            dvY <- dvarX[j]
            if (docons | dobb3) {
              moms.X <- momsX[[i]]
              moms.Y <- momsX[[j]]
            }
          }
        
          
        
        output$dcor[i,j] <- output$dcor[j,i] <- dcov2todcor(dcov2 = dcov2XY, dvX, dvY)
        
        
        
        output$pvalue[i,j] <- output$pvalue[j,i] <- testfunc(dcov2 = dcov2XY, terms = terms, moms.X = moms.X, moms.Y = moms.Y, n = n, smp = perms, prepX[[i]], prepX[[j]])
      }
      }
    }
  } else {
    for (i in setdiff(1:dX,ms.grpX)) {
      for (j in setdiff(1:dY,ms.grpY)) {
        if (alg.fast) {
          terms <- preptoterms.fast(prepX[[i]], prepY[[j]], n, pairwise = use.pw, discrete.X[[i]], discrete.Y[[j]], perm = extendoutput)
        } else if (alg.memsave) {
          terms <- preptoterms.memsave(prepX[[i]], prepY[[j]], metr.X[[i]], metr.Y[[j]], n, pairwise = use.pw, perm = extendoutput) 
        } else if (alg.standard) {
          terms <- preptoterms.standard(prepX[[i]], prepY[[j]], n, pairwise = use.pw, perm = extendoutput)
            }  
        dcov2XY <- termstodcov2(terms$aijbij, vector_prod_sum(terms$aidot, terms$bidot), terms$adotdot * terms$bdotdot, terms$ncc)
        output$dcov[i,j] <- dcov2todcov(dcov2 = dcov2XY)
        if (use.pw) {
          Saa <- vector_prod_sum(terms$aidot, terms$aidot)
          Sbb <- vector_prod_sum(terms$bidot, terms$bidot)
          dvX <-  termstodcov2(terms$aijaij, Saa, terms$adotdot * terms$adotdot, terms$ncc)
          dvY <-  termstodcov2(terms$bijbij, Sbb, terms$bdotdot * terms$bdotdot, terms$ncc)
          if (docons | dobb3) {
            moms.X <- calcmom(aijaij = terms$aijaij, Saa = Saa, adotdot = terms$adotdot, distX = terms$distX, aidot = terms$aidot, n = terms$ncc, dobb3 = dobb3)
            moms.Y <- calcmom(aijaij = terms$bijbij, Saa = Sbb, adotdot = terms$bdotdot, distX = terms$distY, aidot = terms$bidot, n = terms$ncc, dobb3 = dobb3)
          }
          if (doperm) {
            perms <- lapply(1:b, function(t) sample(1:terms$ncc))
          }
        } else {
          dvX <- dvarX[i]
          dvY <- dvarY[j]
          if (docons | dobb3) {
            moms.X <- momsX[[i]]
            moms.Y <- momsY[[j]]
          }
        }
        output$dcor[i,j] <- dcov2todcor(dcov2 = dcov2XY, dvX, dvY)
        
      
        output$pvalue[i,j] <- testfunc(dcov2 = dcov2XY, terms = terms, moms.X = moms.X, moms.Y = moms.Y, smp = perms, prepX[[i]], prepY[[j]])
      }
    }
  }





  if (adjustp %in% c("holm", "hochberg", "hommel", "bonferroni", "BH", "BY", "fdr")) {
    if (withY) {
      output$adj.pvalues <- matrix(p.adjust(output$pvalues,method = adjustp), ncol = q)
    } else {
      ind <- which(lower.tri(output$pvalues), arr.ind=TRUE)
      pvec <- as.vector(output$pvalues[ind])
      pvec <- p.adjust(pvec, method = adjustp)
      output$adj.pvalues <- diag(0,p)
      ind2 <- ind[,2:1]
      output$adj.pvalues[ind] <- output$adj.pvalues[ind2] <- pvec
    }  
  } else if (adjustp != "none")
    warning ("adjustp should be one of \"holm\", \"hochberg\", \"hommel\", \"bonferroni\", \"BH\", \"BY\", \"fdr\" \n
             No p-value correction performed")
 
  class(output) <- "dcmatrix"
  
  output$withY <- withY
  output$dX <- dX
  output$dY <- dY
  output$n <- n
  output$b <- b
  output$test <- test
  output$calc.dcov <- calc.dcov
  output$calc.dcor <- calc.dcor
  output$bias.corr <- bias.corr
  output$affine <- affine
  output$calc.cor <- calc.cor
  
  return(output)
  
 
  
}
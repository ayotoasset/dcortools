
#' Calculate the distance matrix of a given vector and a given metric.
#'
#' @param X a numeric vector or a numeric matrix.
#' @param metr.X metric that should be used to compute the distance matrix.
#' @param n number of samples, i.e. the number of rows of X..
#' @param p number of repetitions, i.e. the number of columns of X.
#' @param ... additional parameters that are used for other metrics (e.g., the bandwidth for Gaussian kernels)
#' @details For metr.X the following metrices are built in: euclidean, gaussian and discrete. However,
#' it is possible to use a function taking two numerical arguments as metr.X.
#'
#' @return The distance matrix corresponding to X.
#' @export
distmat <- function(X,
                    metr.X = "euclidean",
                    p) {
  len <- length(metr.X) 
  
  if (len == 1) {
    if (p == 1) {
      X <- as.numeric(X)
      if (metr.X == "euclidean" | metr.X == "alpha" | metr.X == "minkowski") {
        distX <- Rfast::vecdist(X)
      } else if (metr.X == "gaussian") {
        distX <- 1 - exp(-0.5 * Rfast::vecdist(X) ^ 2)
      } else if (metr.X == "boundsq") {
        distX <- Rfast::vecdist(X) 
        distX <- (distX ^ 2) / (1 + distX ^ 2)
      } else if (metr.X == "discrete") {
        distX <- 1 * (Rfast::vecdist(X)>0)
      } else {
        distfunc <- match.fun(metr.X)
        distX <- distfunc(X = X)
        if (formals(distfunc)$kernel) {
          distX <- kerntodist(distX)
        }
      } 
    } else {
      if (metr.X == "euclidean" | metr.X == "alpha" | metr.X == "minkowski") {
        distX <- Rfast::Dist(X)
      } else if (metr.X == "gaussian") {
        distX <- 1 - exp(-0.5 * Rfast::Dist(X) ^ 2)
      } else if (metr.X == "boundsq") {
        distX <- Rfast::Dist(X) 
        distX <- (distX ^ 2) / (1 + distX ^ 2)
      } else if (metr.X == "discrete") {
        distX <- 1*(Rfast::Dist(X)>0)
      } else {
        distfunc <- match.fun(metr.X)
        distX <- distfunc(X = X)
        if (formals(distfunc)$kernel) {
          distX <- kerntodist(distX)
        }
      } 
    }
  } else {
    prm <- as.numeric(metr.X[2:len])
    metr.X <- metr.X[1]
    if (p == 1) {
      if (metr.X == "alpha") {
        distX <- Rfast::vecdist(X) ^ prm
      } else if (metr.X == "gaussian") {
        distX <- 1 - exp(-0.5 * Rfast::vecdist(X) ^ 2 / prm)
      } else if (metr.X == "boundsq") {
        distX <- Rfast::vecdist(X) 
        distX <- (distX ^ 2) / (prm ^ 2 + distX ^ 2)
      } else if (metr.X == "minkowski") {
        distX <- Rfast::vecdist(X) 
      } else {
        distfunc <- match.fun(metr.X)
        distX <- distfunc(X = X, prm = prm)
        if (formals(distfunc)$kernel) {
          distX <- kerntodist(distX)
        }
      } 
    } else {
      if (metr.X == "alpha") {
        distX <- Rfast::Dist(X) ^ prm
      } else if (metr.X == "gaussian") {
        distX <- 1 - exp(-0.5 * Rfast::Dist(X) ^ 2 / prm)
      } else if (metr.X == "boundsq") {
        distX <- Rfast::Dist(X) 
        distX <- (distX ^ 2) / (prm ^ 2 + distX ^ 2)
      } else if (metr.X == "minkowski") {
        if (prm > 2 | prm <= 1)
          warning("Distance covariance with Minkowski distance outside the interval (1,2] does not define independence")
        distX <- as.matrix(dist(X, method="minkowski", p=prm)) 
      } else {
        distfunc <- match.fun(metr.X)
        distX <- distfunc(X = X, prm = prm)
        if (formals(distfunc)$kernel) {
          distX <- kerntodist(distX)
        }
      } 
    }
  }
  return(distX)
}


kerntodist <- function(kernmat) {
  n <- ncol(kernmat)
  dmat <- matrix(rep(diag(kernmat), n), ncol = n)
  return((dmat + t(dmat) - 2 * kernmat))
}


#' Extract the dimensions of X.
#'
#' @param X a numeric vector or a numeric matrix.
#' @param type.X either "sample" or "distance". If type.X = "sample", X must be
#' a numeric vector or numeric matrix with the corresponding observations. If metr.X = "distance",
#' X must be a distance matrix.
#'
#' @return The centralized distance matrix corresponding to X.
extract_np <- function(X, type.X) {
  if (type.X == "sample") {
    if (is.vector(X) | is.factor(X))
    {
      n <- length(X)
      p <- 1L
    } else if (is.matrix(X)) {
      n <- nrow(X)
      p <- ncol(X)
    } else {
      stop("X must be a vector or matrix for type 'sample'!")
    }
  } else if (type.X == "distance") {
    if (is.matrix(X)) {
      n <- nrow(X)
      p <- NA
    } else {
      stop("X must be a matrix for type 'distance'!")
    }
  } else {
    stop("type.X must be either 'sample' or 'distance'.")
  }
  return(list("Sample.Size" = n, "Dimension" = p))
}


decom.metr<- function(metr.X) {
  if (length(metr.X) == 1) {
    prmX <- 0
  } else {
    prmX <- as.numeric(metr.X[2])
    metr.X <- as.character(metr.X[1])
    if (is.na(prmX)) 
      stop("Parameters of standard metrics must be numeric")
  }
  return(c(metr.X,prmX))
}

normalize.sample <- function(X, n, p) {
  if (p > n) {
    stop("Affinely invariant distance covariance cannot be calculated for p>n")
  }
  if (p > 1) {
    X <- X %*% Rfast::spdinv(mroot(var(X)))
  } else {
    X <- X / sd(X)
  }
}


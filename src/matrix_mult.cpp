// [[Rcpp::depends(RcppEigen)]]

#include <RcppEigen.h>

/* taken from https://stackoverflow.com/a/35924060 */
// [[Rcpp::export]]
SEXP eigenMapMatMult(const Eigen::Map<Eigen::MatrixXd> A, Eigen::Map<Eigen::MatrixXd> B){
  Eigen::MatrixXd C = A * B;

  return Rcpp::wrap(C);
}

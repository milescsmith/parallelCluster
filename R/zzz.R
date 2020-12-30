.onUnload <- function(libpath) {
  library.dynam.unload("parallelCluster", libpath)
}

## no S4 methodology here; speedup :
.noGenerics <- TRUE

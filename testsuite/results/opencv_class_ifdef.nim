type
  Algorithm* {.importcpp: "Algorithm", header: "opencv_class_ifdef.hpp", bycopy.} = object ##
                                                                                   ##
                                                                                   ## @overload
                                                                                   ##


proc write*(this: Algorithm; fs: var FileStorage; name: String) {.noSideEffect,
    importcpp: "write", header: "opencv_class_ifdef.hpp".}
when CV_VERSION_MAJOR < 5:
  proc write*(this: Algorithm) {.noSideEffect, importcpp: "write",
                              header: "opencv_class_ifdef.hpp".}
    ##  @deprecated
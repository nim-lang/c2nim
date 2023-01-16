type
  ParamType*[T: vector[Mat]] {.importcpp: "ParamType<\'0>",
                             header: "opencv_templ_param.hpp", bycopy.} = object

  ParamTypeconst_param_type* = vector[Mat]
  ParamTypemember_type* = vector[Mat]

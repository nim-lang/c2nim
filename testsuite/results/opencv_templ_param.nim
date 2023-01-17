type
  ParamType*[T: vector[Mat]] {.importcpp: "ParamType<\'0>",
                             header: "opencv_templ_param.hpp", bycopy.} = object

  ParamTypeconst_param_type* = vector[Mat]
  ParamTypemember_type* = vector[Mat]
  ParamType*[T: cuint] {.importcpp: "ParamType<\'0>",
                       header: "opencv_templ_param.hpp", bycopy.} = object

  ParamTypeconst_param_type* = cuint
  ParamTypemember_type* = cuint
  ParamType*[T: _Tp; U: `type`[value[_Tp]]] {.importcpp: "ParamType<\'0,\'1>",
      header: "opencv_templ_param.hpp", bycopy.} = object

  ParamTypeconst_param_type* = `type`[_Tp]
  ParamTypemember_type* = `type`[_Tp]

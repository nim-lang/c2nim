type
  ParamType_TvectorMat*[T: vector[Mat]] {.importcpp: "ParamType_TvectorMat<\'0>",
                                        header: "opencv_templ_param.hpp", bycopy.} = object

  ParamType_TvectorMatconst_param_type* = vector[Mat]
  ParamType_TvectorMatmember_type* = vector[Mat]
  ParamType_Tcuint*[T: cuint] {.importcpp: "ParamType_Tcuint<\'0>",
                              header: "opencv_templ_param.hpp", bycopy.} = object

  ParamType_Tcuintconst_param_type* = cuint
  ParamType_Tcuintmember_type* = cuint
  ParamType_T_TpUtypevalue_Tp*[T: _Tp; U: `type`[value[_Tp]]] {.
      importcpp: "ParamType_T_TpUtypevalue_Tp<\'0,\'1>",
      header: "opencv_templ_param.hpp", bycopy.} = object

  ParamType_T_TpUtypevalue_Tpconst_param_type* = `type`[_Tp]
  ParamType_T_TpUtypevalue_Tpmember_type* = `type`[_Tp]

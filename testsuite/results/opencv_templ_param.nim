type
  ParamType_TvectorMat*[T: vector[Mat]] {.bycopy.} = object

  ParamType_TvectorMatconst_param_type* = vector[Mat]
  ParamType_TvectorMatmember_type* = vector[Mat]
  ParamType_Tcuint*[T: cuint] {.bycopy.} = object

  ParamType_Tcuintconst_param_type* = cuint
  ParamType_Tcuintmember_type* = cuint
  ParamType_T_Tp;Utypevalue_Tp*[T: _Tp; U: `type`[value[_Tp]]] {.bycopy.} = object

  ParamType_T_Tp;Utypevalue_Tpconst_param_type* = `type`[_Tp]
  ParamType_T_Tp;Utypevalue_Tpmember_type* = `type`[_Tp]

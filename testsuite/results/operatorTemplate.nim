## ! @relates cv::Vec
## ! @{

proc operatorPE*[_Tp1; _Tp2; cn: static[cint]](a: var Vec[_Tp1, cn]; b: Vec[_Tp2, cn]): var Vec[
    _Tp1, cn] =
  discard

proc `+=`*[_Tp1; _Tp2; cn: static[cint]](a: var Vec[_Tp1, cn]; b: Vec[_Tp2, cn])
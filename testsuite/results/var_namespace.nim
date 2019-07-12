##  namespaces don't work for variables #168

var my_var* {.importcpp: "VarNS::my_var", header: "var_namespace.hpp".}: cint

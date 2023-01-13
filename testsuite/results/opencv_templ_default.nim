import macros

echo "test"

macro test() =
  let q = 
    quote do:
      type
        ParamType*[Tp; EnumTp = void] 
  echo "Q: ", treeRepr q

test()
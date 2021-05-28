proc main*(): cint =
  var v: vector[cint] = [0, 1, 2, 3, 4, 5]
  for i in v:                    ##  access by const reference
    cout shl i shl ' '
  for i in v:                    ##  access by value, the type of i is int
    cout shl i shl ' '
  cout shl '\n'
  for i in v:                    ##  access by forwarding reference, the type of i is int&
    cout shl i shl ' '
  cout shl '\n'
  var cv: var auto = v
  for i in cv:                   ##  access by f-d reference, the type of i is const int&
    cout shl i shl ' '
  cout shl '\n'
  for n in (0, 1, 2, 3, 4, 5):        ##  the initializer may be a braced-init-list
    cout shl n shl ' '
  cout shl '\n'
  var a: UncheckedArray[cint] = [0, 1, 2, 3, 4, 5]
  for n in a:                    ##  the initializer may be an array
    cout shl n shl ' '
  cout shl '\n'
  for n in a:
    cout shl 1 shl ' '
  ##  the loop variable need not be used
  cout shl '\n'
  ##
  ##     for (auto n = v.size(); auto i : v) // the init-statement (C++20)
  ##         std::cout << --n + i << ' ';
  ##     std::cout << '\n';
  
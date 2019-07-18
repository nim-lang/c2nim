class fooBar;

class foo{
public:
  foo(int i){
    val = i;
  }
  int val;
};

int bar(foo f = foo(0)){
  return f.val;
}


int bar(fooBar f = fooBar(0));

class ConsInitList : public foo{
public:
  ConsInitList(int i) : foo(i) {}
};
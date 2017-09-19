class foo {
public:
  foo() throw();
  virtual ~foo() throw(float);
  int m() const throw(int);
};

int bar() throw(A, B);
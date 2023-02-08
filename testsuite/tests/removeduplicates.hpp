#render nobody
#mergeDuplicates

class Test {

public:
    char* cvptr(const int* idx);
    const char* cvptr(const int* idx) const;

};

char* Test::cvptr(const int* idx) {

}
const char* Test::cvptr(const int* idx) const {

}

typedef const Test Test;
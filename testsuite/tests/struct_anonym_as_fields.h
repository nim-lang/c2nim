#anonymousAsFields
#reordercomments

struct normal{
	int a;
	int b;
};

typedef struct outerStruct {
	struct normal a_nomal_one;
	
	int a;
	
	struct {
		union {
			int b;
			float ab;
		};
		
		int c;
	};
	
	union {
		int d;
		
		struct {
			int e;
		} a_struct_in_the_union;
	};
};
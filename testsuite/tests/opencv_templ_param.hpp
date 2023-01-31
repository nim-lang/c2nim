#cppspecialization

template<> struct ParamType<std::vector<Mat> >
{
    typedef const std::vector<Mat>& const_param_type;
    typedef std::vector<Mat> member_type;

    static const Param type = Param::MAT_VECTOR;
};

template<> struct ParamType<unsigned>
{
    typedef unsigned const_param_type;
    typedef unsigned member_type;

    static const Param type = Param::UNSIGNED_INT;
};

template<typename _Tp>
struct ParamType<_Tp, typename std::enable_if< std::is_enum<_Tp>::value >::type>
{
    typedef typename std::underlying_type<_Tp>::type const_param_type;
    typedef typename std::underlying_type<_Tp>::type member_type;

    static const Param type = Param::INT;
};
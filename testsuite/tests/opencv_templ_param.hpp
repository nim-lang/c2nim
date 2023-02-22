#cppspecialization
#header
#importc

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

_AccTp normDecl(const Tp* a, const Tp* b, int n);

_AccTp normRegular(const Tp* a, const Tp* b, int n)
{
}

template<typename _Tp, typename _AccTp>
_AccTp normL2Sqr(const _Tp* a, const _Tp* b, int n)
{
    _AccTp s = 0;
    int i= 0;

    for(; i <= n - 4; i += 4 )
    {
        _AccTp v0 = _AccTp(a[i] - b[i]), v1 = _AccTp(a[i+1] - b[i+1]), v2 = _AccTp(a[i+2] - b[i+2]), v3 = _AccTp(a[i+3] - b[i+3]);
        s += v0*v0 + v1*v1 + v2*v2 + v3*v3;
    }

    for( ; i < n; i++ )
    {
        _AccTp v = _AccTp(a[i] - b[i]);
        s += v*v;
    }
    return s;
}
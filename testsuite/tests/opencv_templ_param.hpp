
template<> struct ParamType<bool>
{
    typedef bool const_param_type;
    typedef bool member_type;

    static const Param type = Param::BOOLEAN;
};
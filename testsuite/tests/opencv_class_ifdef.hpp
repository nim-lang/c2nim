class Algorithm
{
public:

    /**
    * @overload
    */
    void write(FileStorage& fs, const String& name) const;
#if CV_VERSION_MAJOR < 5
    /** @deprecated */
    void write() const;
#endif

protected:
    void writeFormat(FileStorage& fs) const;
};

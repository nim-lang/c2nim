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

    iterator operator++(int);
    friend bool operator== (const iterator& a, const iterator& b) {  return { a.m_curr == b.m_curr }; }
    friend bool operator!= (const iterator& a, const iterator& b) { return /* test */ a.m_curr != b.m_curr; }
    int test(int);

protected:
    void writeFormat(FileStorage& fs) const;
};

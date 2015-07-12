  #discardableprefix Add
  #discardableprefix Set

  bool AddPoint(Sizer* s, int x, int y);
  int SetSize(Widget* w, int w, int h);

// bug # #18

const GLfloat diamond[4][2] = {
{ 0.0, 1.0 }, // Top point
{ 1.0, 0.0 }, // Right point
{ 0.0, -1.0 }, // Bottom point
{ -1.0, 0.0 } }; // Left point


// bug #40
void cdCanvasPattern(cdCanvas* canvas, int w, int h, long const int *pattern);

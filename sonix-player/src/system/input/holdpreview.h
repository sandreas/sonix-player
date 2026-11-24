#ifndef HOLDPREVIEW_H
#define HOLDPREVIEW_H

#include <stdbool.h>

typedef struct {
	void (*seek)(double target);
	void (*note)(const char *file, double pos, double total);
} holdpreview_ops_t;

double holdpreview_target(double current, double step, double total, bool forward);

#endif

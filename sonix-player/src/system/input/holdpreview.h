#ifndef HOLDPREVIEW_H
#define HOLDPREVIEW_H

#include <stdbool.h>

#include "src/system/input/seekpolicy.h"

typedef struct {
	bool (*allowed)(void);
	seek_status_t (*status)(void);
	void (*seek)(double target);
	void (*note)(const char *file, double pos, double total);
} holdpreview_ops_t;

void holdpreview_init(const holdpreview_ops_t *ops);
bool holdpreview_active(void);
bool holdpreview_begin(double step, bool forward, bool live, double total, double current, const char *file);
bool holdpreview_step(double step, bool forward, bool live, double total, double current, const char *file);
void holdpreview_end(void);
void holdpreview_cancel(void);

double holdpreview_target(double current, double step, double total, bool forward);

#endif

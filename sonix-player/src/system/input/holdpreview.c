#include "src/system/input/holdpreview.h"

double holdpreview_target(double current, double step, double total, bool forward) {
	if (total <= 0.0) {
		return 0.0;
	}

	double target = forward ? current + step : current - step;
	if (target < 0.0) {
		target = 0.0;
	}
	if (target > total - 1.0) {
		target = total - 1.0;
	}
	return target;
}

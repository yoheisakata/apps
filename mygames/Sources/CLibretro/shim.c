#include "libretro.h"
#include "shim.h"
#include <stdio.h>
#include <stdarg.h>

/* コアに渡すログ関数。可変長引数の C 関数は Swift で作れないためここで定義する。
   これを渡さない(GET_LOG_INTERFACE に false を返す)と、nestopia などは
   log コールバックを NULL のまま呼び出してクラッシュする(CPU JAM 時など)。 */
static void clibretro_log(enum retro_log_level level, const char *fmt, ...) {
    (void)level;
    va_list args;
    va_start(args, fmt);
    vfprintf(stderr, fmt, args);
    va_end(args);
}

void clibretro_fill_log_interface(void *data) {
    if (data) {
        ((struct retro_log_callback *)data)->log = clibretro_log;
    }
}

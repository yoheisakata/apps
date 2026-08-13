#ifndef CLIBRETRO_SHIM_H
#define CLIBRETRO_SHIM_H

/* RETRO_ENVIRONMENT_GET_LOG_INTERFACE の data (struct retro_log_callback*) に
   stderr へ出力するログ関数を書き込む */
void clibretro_fill_log_interface(void *data);

#endif

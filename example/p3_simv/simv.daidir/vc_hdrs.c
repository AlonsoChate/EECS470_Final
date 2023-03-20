#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <stdio.h>
#include <dlfcn.h>
#include "svdpi.h"

#ifdef __cplusplus
extern "C" {
#endif

/* VCS error reporting routine */
extern void vcsMsgReport1(const char *, const char *, int, void *, void*, const char *);

#ifndef _VC_TYPES_
#define _VC_TYPES_
/* common definitions shared with DirectC.h */

typedef unsigned int U;
typedef unsigned char UB;
typedef unsigned char scalar;
typedef struct { U c; U d;} vec32;

#define scalar_0 0
#define scalar_1 1
#define scalar_z 2
#define scalar_x 3

extern long long int ConvUP2LLI(U* a);
extern void ConvLLI2UP(long long int a1, U* a2);
extern long long int GetLLIresult();
extern void StoreLLIresult(const unsigned int* data);
typedef struct VeriC_Descriptor *vc_handle;

#ifndef SV_3_COMPATIBILITY
#define SV_STRING const char*
#else
#define SV_STRING char*
#endif

#endif /* _VC_TYPES_ */

#ifndef __VCS_IMPORT_DPI_STUB_print_header
#define __VCS_IMPORT_DPI_STUB_print_header
__attribute__((weak)) void print_header(/* INPUT */const char* A_1)
{
    static int _vcs_dpi_stub_initialized_ = 0;
    static void (*_vcs_dpi_fp_)(/* INPUT */const char* A_1) = NULL;
    if (!_vcs_dpi_stub_initialized_) {
        _vcs_dpi_fp_ = (void (*)(const char* A_1)) dlsym(RTLD_NEXT, "print_header");
        _vcs_dpi_stub_initialized_ = 1;
    }
    if (_vcs_dpi_fp_) {
        _vcs_dpi_fp_(A_1);
    } else {
        const char *fileName;
        int lineNumber;
        svGetCallerInfo(&fileName, &lineNumber);
        vcsMsgReport1("DPI-DIFNF", fileName, lineNumber, 0, 0, "print_header");
    }
}
#endif /* __VCS_IMPORT_DPI_STUB_print_header */

#ifndef __VCS_IMPORT_DPI_STUB_print_cycles
#define __VCS_IMPORT_DPI_STUB_print_cycles
__attribute__((weak)) void print_cycles()
{
    static int _vcs_dpi_stub_initialized_ = 0;
    static void (*_vcs_dpi_fp_)() = NULL;
    if (!_vcs_dpi_stub_initialized_) {
        _vcs_dpi_fp_ = (void (*)()) dlsym(RTLD_NEXT, "print_cycles");
        _vcs_dpi_stub_initialized_ = 1;
    }
    if (_vcs_dpi_fp_) {
        _vcs_dpi_fp_();
    } else {
        const char *fileName;
        int lineNumber;
        svGetCallerInfo(&fileName, &lineNumber);
        vcsMsgReport1("DPI-DIFNF", fileName, lineNumber, 0, 0, "print_cycles");
    }
}
#endif /* __VCS_IMPORT_DPI_STUB_print_cycles */

#ifndef __VCS_IMPORT_DPI_STUB_print_stage
#define __VCS_IMPORT_DPI_STUB_print_stage
__attribute__((weak)) void print_stage(/* INPUT */const char* A_1, /* INPUT */int A_2, /* INPUT */int A_3, /* INPUT */int A_4)
{
    static int _vcs_dpi_stub_initialized_ = 0;
    static void (*_vcs_dpi_fp_)(/* INPUT */const char* A_1, /* INPUT */int A_2, /* INPUT */int A_3, /* INPUT */int A_4) = NULL;
    if (!_vcs_dpi_stub_initialized_) {
        _vcs_dpi_fp_ = (void (*)(const char* A_1, int A_2, int A_3, int A_4)) dlsym(RTLD_NEXT, "print_stage");
        _vcs_dpi_stub_initialized_ = 1;
    }
    if (_vcs_dpi_fp_) {
        _vcs_dpi_fp_(A_1, A_2, A_3, A_4);
    } else {
        const char *fileName;
        int lineNumber;
        svGetCallerInfo(&fileName, &lineNumber);
        vcsMsgReport1("DPI-DIFNF", fileName, lineNumber, 0, 0, "print_stage");
    }
}
#endif /* __VCS_IMPORT_DPI_STUB_print_stage */

#ifndef __VCS_IMPORT_DPI_STUB_print_reg
#define __VCS_IMPORT_DPI_STUB_print_reg
__attribute__((weak)) void print_reg(/* INPUT */int A_1, /* INPUT */int A_2, /* INPUT */int A_3, /* INPUT */int A_4)
{
    static int _vcs_dpi_stub_initialized_ = 0;
    static void (*_vcs_dpi_fp_)(/* INPUT */int A_1, /* INPUT */int A_2, /* INPUT */int A_3, /* INPUT */int A_4) = NULL;
    if (!_vcs_dpi_stub_initialized_) {
        _vcs_dpi_fp_ = (void (*)(int A_1, int A_2, int A_3, int A_4)) dlsym(RTLD_NEXT, "print_reg");
        _vcs_dpi_stub_initialized_ = 1;
    }
    if (_vcs_dpi_fp_) {
        _vcs_dpi_fp_(A_1, A_2, A_3, A_4);
    } else {
        const char *fileName;
        int lineNumber;
        svGetCallerInfo(&fileName, &lineNumber);
        vcsMsgReport1("DPI-DIFNF", fileName, lineNumber, 0, 0, "print_reg");
    }
}
#endif /* __VCS_IMPORT_DPI_STUB_print_reg */

#ifndef __VCS_IMPORT_DPI_STUB_print_membus
#define __VCS_IMPORT_DPI_STUB_print_membus
__attribute__((weak)) void print_membus(/* INPUT */int A_1, /* INPUT */int A_2, /* INPUT */int A_3, /* INPUT */int A_4, /* INPUT */int A_5, /* INPUT */int A_6)
{
    static int _vcs_dpi_stub_initialized_ = 0;
    static void (*_vcs_dpi_fp_)(/* INPUT */int A_1, /* INPUT */int A_2, /* INPUT */int A_3, /* INPUT */int A_4, /* INPUT */int A_5, /* INPUT */int A_6) = NULL;
    if (!_vcs_dpi_stub_initialized_) {
        _vcs_dpi_fp_ = (void (*)(int A_1, int A_2, int A_3, int A_4, int A_5, int A_6)) dlsym(RTLD_NEXT, "print_membus");
        _vcs_dpi_stub_initialized_ = 1;
    }
    if (_vcs_dpi_fp_) {
        _vcs_dpi_fp_(A_1, A_2, A_3, A_4, A_5, A_6);
    } else {
        const char *fileName;
        int lineNumber;
        svGetCallerInfo(&fileName, &lineNumber);
        vcsMsgReport1("DPI-DIFNF", fileName, lineNumber, 0, 0, "print_membus");
    }
}
#endif /* __VCS_IMPORT_DPI_STUB_print_membus */

#ifndef __VCS_IMPORT_DPI_STUB_print_close
#define __VCS_IMPORT_DPI_STUB_print_close
__attribute__((weak)) void print_close()
{
    static int _vcs_dpi_stub_initialized_ = 0;
    static void (*_vcs_dpi_fp_)() = NULL;
    if (!_vcs_dpi_stub_initialized_) {
        _vcs_dpi_fp_ = (void (*)()) dlsym(RTLD_NEXT, "print_close");
        _vcs_dpi_stub_initialized_ = 1;
    }
    if (_vcs_dpi_fp_) {
        _vcs_dpi_fp_();
    } else {
        const char *fileName;
        int lineNumber;
        svGetCallerInfo(&fileName, &lineNumber);
        vcsMsgReport1("DPI-DIFNF", fileName, lineNumber, 0, 0, "print_close");
    }
}
#endif /* __VCS_IMPORT_DPI_STUB_print_close */


#ifdef __cplusplus
}
#endif


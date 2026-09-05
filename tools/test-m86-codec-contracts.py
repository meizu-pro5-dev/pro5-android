#!/usr/bin/env python3
"""Host checks of production functions with mocked Android and driver APIs."""
from pathlib import Path
import argparse
import subprocess
import tempfile

parser = argparse.ArgumentParser(description="Compile and test m86 OMX/gralloc contracts from an Android source tree.")
parser.add_argument("source_root", type=Path)
args = parser.parse_args()
R = args.source_root.resolve()
test_directory = tempfile.TemporaryDirectory(prefix="m86-codec-contracts-")
W = Path(test_directory.name)
O=R/'hardware/samsung_slsi-linaro/openmax'
incs=[R/'frameworks/native/headers/media_plugin/media/openmax',O/'openmax/include/exynos',R/'hardware/samsung_slsi-linaro/exynos/include',R/'system/core/libsystem/include',O/'videocodec/include']
common='''#include <cassert>
#include <cstdint>
#include <cstring>
#include <cerrno>
#include <memory>
#include "Exynos_OMX_Def.h"
#include "exynos_format.h"
#include "system/graphics.h"
#define FunctionIn() ((void)0)
#define FunctionOut() ((void)0)
#define Exynos_OSAL_Log(...) ((void)0)
#define Exynos_OSAL_Memset std::memset
#define ALOGE(...) ((void)0)
#define ALOGW(...) ((void)0)
#define ALOGV(...) ((void)0)
'''
def run(name,source,flags=()):
 p=W/(name+'.cpp');p.write_text(source)
 cmd=['g++','-std=c++17','-O2',*[f'-I{x}' for x in incs],*flags,str(p),'-o',str(W/name)]
 subprocess.run(cmd,check=True)
 subprocess.run([str(W/name)],check=True)
 print('PASS',name,flush=True)
s=(O/'openmax/osal/Exynos_OSAL_ETC.c').read_text()
a=s.index('static struct {',s.index('Exynos_OSAL_Video2OMXFormat')) if 'Exynos_OSAL_Video2OMXFormat' in s else s.index('static struct {',s.index('HAL_COLORFORMAT_MAP')-220)
a=s.rfind('static struct {',0,s.index('} HAL_COLORFORMAT_MAP'))
b=s.index('int Exynos_OSAL_DataSpaceToColorSpace',a)
test='''
int main() {
#ifdef USE_NONPRIVATE_NV12
 assert(Exynos_OSAL_OMX2HALPixelFormat(OMX_COLOR_FormatYUV420SemiPlanar,PLANE_MULTIPLE)==0x105);
#else
 assert(Exynos_OSAL_OMX2HALPixelFormat(OMX_COLOR_FormatYUV420SemiPlanar,PLANE_MULTIPLE)==0x121);
#endif
 assert(Exynos_OSAL_HAL2OMXColorFormat(0x121)==OMX_COLOR_FormatYUV420SemiPlanar);
 assert(Exynos_OSAL_OMX2HALPixelFormat(OMX_COLOR_FormatYUV420SemiPlanar,PLANE_SINGLE)==HAL_PIXEL_FORMAT_EXYNOS_YCbCr_420_SPN);
 assert(Exynos_OSAL_OMX2HALPixelFormat((OMX_COLOR_FORMATTYPE)OMX_SEC_COLOR_FormatNV21Linear,PLANE_MULTIPLE)==HAL_PIXEL_FORMAT_EXYNOS_YCrCb_420_SP_M);
 assert(Exynos_OSAL_OMX2HALPixelFormat((OMX_COLOR_FORMATTYPE)OMX_SEC_COLOR_FormatS10bitYUV420SemiPlanar,PLANE_MULTIPLE)==HAL_PIXEL_FORMAT_EXYNOS_YCbCr_420_SP_M_S10B);
}
'''
run('format_m86',common+s[a:b]+test,['-DUSE_PRIV_FORMAT','-DUSE_NONPRIVATE_NV12'])
run('format_default',common+s[a:b]+test,['-DUSE_PRIV_FORMAT'])
s=(O/'openmax/osal/Exynos_OSAL_Android.cpp').read_text();a=s.index('static OMX_ERRORTYPE lockBuffer(');b=s.index('static OMX_ERRORTYPE unlockBuffer(',a)
mock='''
#define GRALLOC_VERSION0
#define OMX_GRALLOC_USAGE_LOCK 3
#define OMX_GRALLOC_USAGE_PROTECTED 0x4000
#define INT_TO_PTR(x) ((void*)(uintptr_t)(x))
using native_handle_t = struct Handle { int format=21, fd=10, fd1=11, fd2=-1, flags=0, stride=1280; };
using private_handle_t = native_handle_t;
using buffer_handle_t = const native_handle_t*;
namespace hardware { struct hidl_handle {}; }
enum class Error { NONE, BAD_VALUE };
struct YCbCrLayout { void *y=nullptr,*cb=nullptr,*cr=nullptr; };
struct EXYNOS_OMX_MULTIPLANE_BUFFER { void *addr[3]={}; unsigned long fd[3]={}; };
struct Status { bool ok; bool isOk()const{return ok;} };
template<class T> using sp=std::shared_ptr<T>;
struct IMapper {
 struct Rect { int left,top,width,height; };
 bool transport=true; Error result=Error::NONE; bool remote=false;
 static sp<IMapper> getService(){static auto m=std::make_shared<IMapper>();return m;}
 bool isRemote()const{return remote;}
 template<class F> Status lock(native_handle_t*,int,Rect,hardware::hidl_handle,F cb){cb(result,(void*)0x1000);return{transport};}
 template<class F> Status lockYCbCr(native_handle_t*,int,Rect,hardware::hidl_handle,F cb){cb(result,YCbCrLayout{(void*)0x1000,(void*)0x2000,(void*)0x3000});return{transport};}
};
OMX_COLOR_FORMATTYPE getBufferFormat(void *p){return (OMX_COLOR_FORMATTYPE)((private_handle_t*)p)->format;}
int lockCnt=0;
'''
test='''
int main(){
 auto mapper=IMapper::getService();private_handle_t h;
 OMX_COLOR_FORMATTYPE formats[]={OMX_COLOR_FormatYUV420SemiPlanar,(OMX_COLOR_FORMATTYPE)OMX_SEC_COLOR_FormatNV21Linear,OMX_COLOR_Format32BitRGBA8888};
 for(auto fmt:formats)for(bool transport:{false,true})for(auto status:{Error::NONE,Error::BAD_VALUE}){
  mapper->transport=transport;mapper->result=status;lockCnt=0;
  EXYNOS_OMX_MULTIPLANE_BUFFER out;OMX_U32 stride=0;
  auto ret=lockBuffer(&h,1280,720,fmt,&stride,&out);
  if(transport && status==Error::NONE){assert(ret==OMX_ErrorNone);assert(out.addr[0]==(void*)0x1000);assert(stride==1280);assert(lockCnt==1);}
  else{assert(ret!=OMX_ErrorNone);assert(lockCnt==0);}
 }
}
'''
run('mapper_errors',common+mock+s[a:b]+test)
s=(O/'videocodec/dec/ExynosVideoDecoder.c').read_text();a=s.index('static ExynosVideoErrorType MFC_Decoder_Get_Geometry_Outbuf(');b=s.index('/*\n * [Decoder Buffer OPS] Get BlackBarCrop',a)
mock='''
#include "ExynosVideoApi.h"
struct CodecOSALVideoContext { struct { ExynosVideoGeometry outbufGeometry; int nOutbufPlanes; } videoCtx; };
struct CodecOSAL_Format {int type,width,height,stride,field,format; unsigned int planeSize[3];};
struct CodecOSAL_Crop {int type,top,left,width,height;};
const int CODEC_OSAL_BUF_TYPE_DST=2,CODEC_OSAL_CID_DEC_GET_10BIT_INFO=99;
int queryError=0,queryValue=0,queryCalls=0,formatError=0;
ExynosVideoColorFormatType pixelFormat=VIDEO_COLORFORMAT_NV12M;
int Codec_OSAL_GetFormat(CodecOSALVideoContext*,CodecOSAL_Format *f){if(formatError){errno=formatError;return -1;}f->width=1280;f->height=720;f->stride=1280;f->planeSize[0]=1280*720;f->planeSize[1]=1280*360;return 0;}
int Codec_OSAL_GetCrop(CodecOSALVideoContext*,CodecOSAL_Crop *c){c->width=1280;c->height=720;return 0;}
ExynosVideoColorFormatType Codec_OSAL_PixelFormatToColorFormat(int){return pixelFormat;}
int Codec_OSAL_GetControl(CodecOSALVideoContext*,int,int *v){queryCalls++;if(queryError){errno=queryError;return -1;}*v=queryValue;return 0;}
'''
test='''
int main(){
 CodecOSALVideoContext c={};c.videoCtx.nOutbufPlanes=2;ExynosVideoGeometry g={};
 for(int e:{0,EINVAL,ENOTTY}){queryError=e;queryValue=0;assert(MFC_Decoder_Get_Geometry_Outbuf(&c,&g)==VIDEO_ERROR_NONE);assert(g.eFilledDataType==DATA_8BIT);assert(g.eColorFormat==VIDEO_COLORFORMAT_NV12M);}
 queryError=EIO;assert(MFC_Decoder_Get_Geometry_Outbuf(&c,&g)==VIDEO_ERROR_APIFAIL);
 queryError=0;queryValue=1;assert(MFC_Decoder_Get_Geometry_Outbuf(&c,&g)==VIDEO_ERROR_NONE);assert(g.eFilledDataType==DATA_8BIT_WITH_2BIT);
 queryError=EIO;queryCalls=0;pixelFormat=VIDEO_COLORFORMAT_NV12M_P010;assert(MFC_Decoder_Get_Geometry_Outbuf(&c,&g)==VIDEO_ERROR_NONE);assert(g.eFilledDataType==DATA_10BIT);assert(queryCalls==0);
 formatError=EAGAIN;assert(MFC_Decoder_Get_Geometry_Outbuf(&c,&g)==VIDEO_ERROR_HEADERINFO);
}
'''
run('geometry_queries',common+mock+s[a:b]+test)
s=(R/'hardware/meizu/m86/graphics/gralloc/a10-contract/mapper.cpp').read_text();a=s.index('int gralloc_lock_ycbcr(');b=s.index('\n}',a)+2
mock='''
#include <sys/mman.h>
#define ALOGD(...) ((void)0)
#define __unused
#define INT_TO_PTR(x) ((void*)(uintptr_t)(x))
#define GRALLOC_USAGE_PROTECTED 0x4000
#define GRALLOC_USAGE_NOZEROED 0x8000
struct gralloc_module_t {};
struct private_handle_t {
 int format=0x105,flags=0,stride=1280,width=1280,height=720;
 uint64_t base=0x100000,base1=0x200000;
 static int validate(const private_handle_t *h){return h?0:-EINVAL;}
};
using buffer_handle_t=const private_handle_t*;
int gralloc_map(const gralloc_module_t*,private_handle_t*){return -ENOMEM;}
'''
test='''
int main(){
 private_handle_t h;android_ycbcr y={};
 assert(gralloc_lock_ycbcr(nullptr,&h,3,0,0,1280,720,&y)==0);
 assert(y.y==(void*)h.base && y.cb==(void*)h.base1 && y.cr==(void*)(h.base1+1));
 assert(y.ystride==1280 && y.chroma_step==2);
 h.format=0x121;assert(gralloc_lock_ycbcr(nullptr,&h,3,0,0,1280,720,&y)==-EINVAL);
 h.format=0x105;h.base1=0;assert(gralloc_lock_ycbcr(nullptr,&h,3,0,0,1280,720,&y)==-EINVAL);
}
'''
run('gralloc_nv12_contract',common+mock+s[a:b]+test)
s=(O/'openmax/component/video/dec/Exynos_OMX_Vdec.c').read_text();a=s.index('                        ret = Exynos_Shared_BufferToData(exynosOutputPort, dstInputUseBuffer, &dstInputData);');b=s.index('#ifdef USE_ANDROID',a)
mock='''
#define CHECK_PORT_BEING_FLUSHED(p) ((p)->flushing)
#define GENERAL_STATE 0
struct Port {bool flushing=false;int exceptionFlag=0;} port,*exynosOutputPort=&port;
struct Buffer {OMX_BOOL dataValid=OMX_TRUE;void *bufferMutex=nullptr;} buffer,*dstInputUseBuffer=&buffer;
struct Video {bool bExitBufferProcessThread=false;} video,*pVideoDec=&video;
int events=0;OMX_ERRORTYPE status=OMX_ErrorUndefined;bool unlocked=false;
void handler(void*,void*,int,OMX_ERRORTYPE err,int,void*){assert(unlocked);assert(err==status);events++;}
struct Callbacks {decltype(&handler) EventHandler=handler;} callbacks;
struct Component {Callbacks *pCallbacks=&callbacks;void *callbackData=nullptr;} component,*pExynosComponent=&component;
void *pOMXComponent=nullptr;int dstInputData=0;
OMX_ERRORTYPE Exynos_Shared_BufferToData(Port*,Buffer*,int*){return status;}
void Exynos_OSAL_MutexUnlock(void*){unlocked=true;}
'''
test='''
int main(){
 for(bool flush:{false,true})for(int exception:{0,1})for(bool exiting:{false,true}){
  port.flushing=flush;port.exceptionFlag=exception;video.bExitBufferProcessThread=exiting;
  events=0;unlocked=false;step();assert(unlocked);
  assert(events==(!flush && exception==0 && !exiting?1:0));
 }
 status=OMX_ErrorNone;events=0;step();assert(events==0);
}
'''
run('output_import_errors',common+mock+'void step(){OMX_ERRORTYPE ret;do{\n'+s[a:b]+'}while(false);}\n'+test)

print('All production-function contract tests passed')

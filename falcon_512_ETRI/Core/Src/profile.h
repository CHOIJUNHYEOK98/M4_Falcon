#ifndef SRC_PROFILE_H_
#define SRC_PROFILE_H_

#define TIMES 10

#define profile_all

#ifdef profile_all

#define profile_keygen
#define profile_sign
#define profile_verify
#define profile_ftt
#define profile_ntt
#define profile_hash

#else

#define profile_keygen
#define profile_sign
#define profile_verify
#define profile_ftt
#define profile_ntt
#define profile_hash

#endif


#endif

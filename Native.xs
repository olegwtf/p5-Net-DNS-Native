#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "ppport.h"
#include <pthread.h>

typedef struct {
	HV* fd_set;
	pthread_mutex_t* mutex;
} DNS_OBJ;

MODULE = Net::DNS::Native	PACKAGE = Net::DNS::Native

SV*
new(char* class)
	PREINIT:
		DNS_OBJ *self;
	CODE:
		Newx(self, 1, DNS_OBJ);
		self->fd_set = newHV();
		pthread_mutex_init(self->mutex, NULL);
		
		RETVAL = sv_newmortal();
		sv_setref_pv(RETVAL, class, (void *)self);
		SvREFCNT_inc(RETVAL);
	OUTPUT:
		RETVAL

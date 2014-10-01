#include <pthread.h>
#include <semaphore.h>
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "ppport.h"
#include "bstree.h"

#pragma push_macro("free")
#pragma push_macro("malloc")
#undef free
#undef malloc
#include "queue.h" // will be used outside of the main thread
#pragma pop_macro("free")
#pragma pop_macro("malloc")

// write() is deprecated in favor of _write() - windows way
#if defined(WIN32) && !defined(UNDER_CE)
# include <io.h>
# define write _write
#endif

// unnamed semaphores are not implemented in this POSIX compatible UNIX system
#ifdef PERL_DARWIN
# include <dispatch/dispatch.h>
# define sem_t dispatch_semaphore_t
# define sem_init(sem, pshared, value) ((*sem = dispatch_semaphore_create(value)) == NULL ? -1 : 0)
# define sem_wait(sem) dispatch_semaphore_wait(*sem, DISPATCH_TIME_FOREVER)
# define sem_post(sem) dispatch_semaphore_signal(*sem)
# define sem_destroy(sem) dispatch_release(*sem)
#endif

typedef struct {
	pthread_mutex_t mutex;
	pthread_attr_t thread_attrs;
	pthread_t *threads_pool;
	sem_t semaphore;
	bstree* fd_map;
	queue* in_queue;
	int pool;
	char extra_thread;
	char notify_on_begin;
	int extra_threads_cnt;
	int busy_threads;
	queue* tout_queue;
} Net_DNS_Native;

typedef struct {
	Net_DNS_Native *self;
	char *host;
	char *service;
	struct addrinfo *hints;
	int fd0;
	char extra;
} DNS_thread_arg;

typedef struct {
	int fd1;
	int error;
	struct addrinfo *hostinfo;
	int type;
	DNS_thread_arg *arg;
} DNS_result;

typedef struct {
	int fd0;
	SV* sock0;
} DNS_timedout;

void *_getaddrinfo(void *v_arg) {
	DNS_thread_arg *arg = (DNS_thread_arg *)v_arg;
	
	pthread_mutex_lock(&arg->self->mutex);
	DNS_result *res = bstree_get(arg->self->fd_map, arg->fd0);
	pthread_mutex_unlock(&arg->self->mutex);
	
	if (arg->self->notify_on_begin)
		write(res->fd1, "1", 1);
	res->error = getaddrinfo(arg->host, arg->service, arg->hints, &res->hostinfo);
	
	pthread_mutex_lock(&arg->self->mutex);
	res->arg = arg;
	if (arg->extra) arg->self->extra_threads_cnt--;
	write(res->fd1, "2", 1);
	pthread_mutex_unlock(&arg->self->mutex);
	
	return NULL;
}

void *_pool_worker(void *v_arg) {
	Net_DNS_Native *self = (Net_DNS_Native*)v_arg;
	
	while (sem_wait(&self->semaphore) == 0) {
		pthread_mutex_lock(&self->mutex);
		void *arg = queue_shift(self->in_queue);
		if (arg != NULL) self->busy_threads++;
		pthread_mutex_unlock(&self->mutex);
		
		if (arg == NULL) {
			// this was request to quit thread
			break;
		}
		
		_getaddrinfo(arg);
		
		pthread_mutex_lock(&self->mutex);
		self->busy_threads--;
		pthread_mutex_unlock(&self->mutex);
	}
	
	return NULL;
}

void _free_timedout(Net_DNS_Native *self) {
	if (queue_size(self->tout_queue)) {
		queue_iterator *it = queue_iterator_new(self->tout_queue);
		DNS_timedout *tout;
		DNS_result *res;
		
		while (!queue_iterator_end(it)) {
			tout = queue_at(self->tout_queue, it);
			res = bstree_get(self->fd_map, tout->fd0);
			if (res == NULL) {
				goto FREE_TOUT;
			}
			
			if (res->arg) {
				bstree_del(self->fd_map, tout->fd0);
				if (!res->error && res->hostinfo)
					freeaddrinfo(res->hostinfo);
				
				close(res->fd1);
				if (res->arg->hints)   free(res->arg->hints);
				if (res->arg->host)    Safefree(res->arg->host);
				if (res->arg->service) Safefree(res->arg->service);
				free(res->arg);
				free(res);
				
				FREE_TOUT:
					SvREFCNT_dec(tout->sock0);
					queue_del(self->tout_queue, it);
					free(tout);
					continue;
			}
			
			queue_iterator_next(it);
		}
		
		queue_iterator_destroy(it);
	}
}

MODULE = Net::DNS::Native	PACKAGE = Net::DNS::Native

PROTOTYPES: DISABLE

SV*
new(char* class, ...)
	PREINIT:
		Net_DNS_Native *self;
	CODE:
		if (items % 2 == 0)
			croak("odd number of parameters");
		
		Newx(self, 1, Net_DNS_Native);
		
		int i, rc;
		self->pool = 0;
		self->notify_on_begin = 0;
		self->extra_thread = 0;
		self->extra_threads_cnt = 0;
		self->busy_threads = 0;
		char *opt;
		
		for (i=1; i<items; i+=2) {
			opt = SvPV_nolen(ST(i));
			
			if (strEQ(opt, "pool")) {
				self->pool = SvIV(ST(i+1));
				if (self->pool < 0) self->pool = 0;
			}
			else if (strEQ(opt, "extra_thread")) {
				self->extra_thread = SvIV(ST(i+1));
			}
			else if (strEQ(opt, "notify_on_begin")) {
				self->notify_on_begin = SvIV(ST(i+1));
			}
			else {
				warn("unsupported option: %s", SvPV_nolen(ST(i)));
			}
		}
		
		char attr_ok = 0, mutex_ok = 0, sem_ok = 0;
		
		rc = pthread_attr_init(&self->thread_attrs);
		if (rc != 0) {
			warn("pthread_attr_init(): %s", strerror(rc));
			goto FAIL;
		}
		attr_ok = 1;
		rc = pthread_attr_setdetachstate(&self->thread_attrs, PTHREAD_CREATE_DETACHED);
		if (rc != 0) {
			warn("pthread_attr_setdetachstate(): %s", strerror(rc));
			goto FAIL;
		}
		rc = pthread_mutex_init(&self->mutex, NULL);
		if (rc != 0) {
			warn("pthread_mutex_init(): %s", strerror(rc));
			goto FAIL;
		}
		mutex_ok = 1;
		
		self->in_queue = NULL;
		self->threads_pool = NULL;
		
		if (self->pool) {
			if (sem_init(&self->semaphore, 0, 0) != 0) {
				warn("sem_init(): %s", strerror(errno));
				goto FAIL;
			}
			sem_ok = 1;
			
			self->threads_pool = malloc(self->pool*sizeof(pthread_t));
			pthread_t tid;
			int j = 0;
			
			for (i=0; i<self->pool; i++) {
				rc = pthread_create(&tid, NULL, _pool_worker, (void*)self);
				if (rc == 0) {
					self->threads_pool[j++] = tid;
				}
				else {
					warn("Can't create thread #%d: %s", i+1, strerror(rc));
				}
			}
			
			if (j == 0) {
				goto FAIL;
			}
			
			self->pool = j;
			self->in_queue = queue_new();
		}
		
		self->fd_map = bstree_new();
		self->tout_queue = queue_new();
		RETVAL = newSV(0);
		sv_setref_pv(RETVAL, class, (void *)self);
		
		if (0) {
			FAIL:
				if (attr_ok) pthread_attr_destroy(&self->thread_attrs);
				if (mutex_ok) pthread_mutex_destroy(&self->mutex);
				if (sem_ok) sem_destroy(&self->semaphore);
				if (self->threads_pool) free(self->threads_pool);
				Safefree(self);
				RETVAL = &PL_sv_undef;
		}
	OUTPUT:
		RETVAL

int
_getaddrinfo(Net_DNS_Native *self, char *host, char *service, SV* sv_hints, int type)
	INIT:
		int fd[2];
	CODE:
		if (socketpair(AF_UNIX, SOCK_STREAM, PF_UNSPEC, fd) != 0)
			croak("socketpair(): %s", strerror(errno));
		
		struct addrinfo *hints = NULL;
		
		if (SvOK(sv_hints)) {
			// defined
			if (!SvROK(sv_hints) || SvTYPE(SvRV(sv_hints)) != SVt_PVHV) {
				// not reference or not a hash inside reference
				croak("hints should be reference to hash");
			}
			
			hints = malloc(sizeof(struct addrinfo));
			hints->ai_flags = 0;
			hints->ai_family = AF_UNSPEC;
			hints->ai_socktype = 0;
			hints->ai_protocol = 0;
			hints->ai_addrlen = 0;
			hints->ai_addr = NULL;
			hints->ai_canonname = NULL;
			hints->ai_next = NULL;
			
			HV* hv_hints = (HV*)SvRV(sv_hints);
			
			SV **flags_ptr = hv_fetch(hv_hints, "flags", 5, 0);
			if (flags_ptr != NULL) {
				hints->ai_flags = SvIV(*flags_ptr);
			}
			
			SV **family_ptr = hv_fetch(hv_hints, "family", 6, 0);
			if (family_ptr != NULL) {
				hints->ai_family = SvIV(*family_ptr);
			}
			
			SV **socktype_ptr = hv_fetch(hv_hints, "socktype", 8, 0);
			if (socktype_ptr != NULL) {
				hints->ai_socktype = SvIV(*socktype_ptr);
			}
			
			SV **protocol_ptr = hv_fetch(hv_hints, "protocol", 8, 0);
			if (protocol_ptr != NULL) {
				hints->ai_protocol = SvIV(*protocol_ptr);
			}
		}
		
		DNS_result *res = malloc(sizeof(DNS_result));
		res->fd1 = fd[1];
		res->error = 0;
		res->hostinfo = NULL;
		res->type = type;
		res->arg = NULL;
		
		DNS_thread_arg *arg = malloc(sizeof(DNS_thread_arg));
		arg->self = self;
		arg->host = strlen(host) ? savepv(host) : NULL;
		arg->service = strlen(service) ? savepv(service) : NULL;
		arg->hints = hints;
		arg->fd0 = fd[0];
		arg->extra = 0;
		
		pthread_mutex_lock(&self->mutex);
		_free_timedout(self);
		bstree_put(self->fd_map, fd[0], res);
		if (self->pool) {
			if (self->busy_threads == self->pool && (self->extra_thread || queue_size(self->tout_queue) > self->extra_threads_cnt)) {
				arg->extra = 1;
				self->extra_threads_cnt++;
			}
			else {
				queue_push(self->in_queue, arg);
				sem_post(&self->semaphore);
			}
		}
		pthread_mutex_unlock(&self->mutex);
		
		if (!self->pool || arg->extra) {
			pthread_t tid;
			int rc = pthread_create(&tid, &self->thread_attrs, _getaddrinfo, (void *)arg);
			if (rc != 0) {
				if (arg->host)    free(arg->host);
				if (arg->service) free(arg->service);
				free(arg);
				free(res);
				if (hints) free(hints);
				bstree_del(self->fd_map, fd[0]);
				close(fd[0]);
				close(fd[1]);
				croak("pthread_create(): %s", strerror(rc));
			}
		}
		
		RETVAL = fd[0];
	OUTPUT:
		RETVAL

void
_get_result(Net_DNS_Native *self, int fd)
	PPCODE:
		pthread_mutex_lock(&self->mutex);
		DNS_result *res = bstree_get(self->fd_map, fd);
		bstree_del(self->fd_map, fd);
		pthread_mutex_unlock(&self->mutex);
		
		if (res == NULL) croak("attempt to get result which doesn't exists");
		if (!res->arg) {
			pthread_mutex_lock(&self->mutex);
			bstree_put(self->fd_map, fd, res);
			pthread_mutex_unlock(&self->mutex);
			croak("attempt to get not ready result");
		}
		
		XPUSHs(sv_2mortal(newSViv(res->type)));
		SV *err = newSV(0);
		sv_setiv(err, (IV)res->error);
		sv_setpv(err, res->error ? gai_strerror(res->error) : "");
		SvIOK_on(err);
		XPUSHs(sv_2mortal(err));
		
		if (!res->error) {
			struct addrinfo *info;
			for (info = res->hostinfo; info != NULL; info = info->ai_next) {
				HV *hv_info = newHV();
				hv_store(hv_info, "family", 6, newSViv(info->ai_family), 0);
				hv_store(hv_info, "socktype", 8, newSViv(info->ai_socktype), 0);
				hv_store(hv_info, "protocol", 8, newSViv(info->ai_protocol), 0);
				hv_store(hv_info, "addr", 4, newSVpvn((char*)info->ai_addr, info->ai_addrlen), 0);
				hv_store(hv_info, "canonname", 9, info->ai_canonname ? newSVpv(info->ai_canonname, 0) : newSV(0), 0);
				XPUSHs(sv_2mortal(newRV_noinc((SV*)hv_info)));
			}
			
			if (res->hostinfo) freeaddrinfo(res->hostinfo);
		}
		
		//close(fd); // will be closed by perl
		close(res->fd1);
		if (res->arg->hints)   free(res->arg->hints);
		if (res->arg->host)    Safefree(res->arg->host);
		if (res->arg->service) Safefree(res->arg->service);
		free(res->arg);
		free(res);

void
_timedout(Net_DNS_Native *self, SV *sock, int fd)
	PPCODE:
		char unknown = 0;
		
		pthread_mutex_lock(&self->mutex);
		if (bstree_get(self->fd_map, fd) == NULL) {
			unknown = 1;
		}
		else {
			sock = SvREFCNT_inc(sock);
			DNS_timedout *tout = malloc(sizeof(DNS_timedout));
			tout->fd0 = fd;
			tout->sock0 = sock;
			queue_push(self->tout_queue, tout);
		}
		pthread_mutex_unlock(&self->mutex);
		
		if (unknown)
			croak("attempt to set timeout on unknown source");

void
DESTROY(Net_DNS_Native *self)
	CODE:
		pthread_mutex_lock(&self->mutex);
		_free_timedout(self);
		pthread_mutex_unlock(&self->mutex);
		
		if (self->pool) {
			pthread_mutex_lock(&self->mutex);
			if (queue_size(self->in_queue) > 0) {
				warn("destroying object while queue for resolver has %d elements", queue_size(self->in_queue));
				queue_clear(self->in_queue);
			}
			pthread_mutex_unlock(&self->mutex);
			
			int i;
			for (i=0; i<self->pool; i++) {
				sem_post(&self->semaphore);
			}
			
			void *rv;
			
			for (i=0; i<self->pool; i++) {
				pthread_join(self->threads_pool[i], &rv);
			}
			
			queue_destroy(self->in_queue);
			free(self->threads_pool);
			sem_destroy(&self->semaphore);
		}
		
		if (bstree_size(self->fd_map) > 0) {
			warn("destroying object with %d non-received results", bstree_size(self->fd_map));
		}
		
		pthread_attr_destroy(&self->thread_attrs);
		pthread_mutex_destroy(&self->mutex);
		bstree_destroy(self->fd_map);
		queue_destroy(self->tout_queue);
		Safefree(self);

void
pack_sockaddr_in6(int port, SV *sv_address)
	PPCODE:
		STRLEN len;
		char *address = SvPV(sv_address, len);
		if (len != 16)
			croak("address length is %lu should be 16", len);
		
		struct sockaddr_in6 *addr = malloc(sizeof(struct sockaddr_in6));
		memcpy(addr->sin6_addr.s6_addr, address, 16);
		addr->sin6_family = AF_INET6;
		addr->sin6_port = port;
		
		XPUSHs(sv_2mortal(newSVpvn((char*) addr, sizeof(struct sockaddr_in6))));

void
unpack_sockaddr_in6(SV *sv_addr)
	PPCODE:
		STRLEN len;
		char *addr = SvPV(sv_addr, len);
		if (len != sizeof(struct sockaddr_in6))
			croak("address length is %lu should be %lu", len, sizeof(struct sockaddr_in6));
		
		struct sockaddr_in6 *struct_addr = (struct sockaddr_in6*) addr;
		XPUSHs(sv_2mortal(newSViv(struct_addr->sin6_port)));
		XPUSHs(sv_2mortal(newSVpvn((char*)struct_addr->sin6_addr.s6_addr, 16)));

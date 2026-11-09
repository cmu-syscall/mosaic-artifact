#ifndef MOSAIC_TBLIS_WRAPPERS_H
#define MOSAIC_TBLIS_WRAPPERS_H

#include <stdlib.h>
#include <tblis.h>

float tblis_vector_dot_transfer(const tblis_comm* comm, const tblis_config* cfg,
                               const tblis_vector* A, const tblis_vector* B,
                               tblis_scalar* result){
    tblis_vector_dot(comm, cfg, A, B, result);
    return result->data.s;
}
void tblis_init_tensor_s_helper_row_major(tblis_tensor * t, int * dim, int num_dim, void * data){ 
    len_type * len = malloc(sizeof(len_type)*num_dim); 
    stride_type * stride = malloc(sizeof(stride_type)*num_dim); 
    if (!len || !stride) abort();
    stride_type stride_product = 1;
    for (int i = num_dim - 1; i >= 0; --i){
        len[i] = dim[i];
        stride[i] = stride_product;
        stride_product *= dim[i];
    }
    tblis_init_tensor_s(t, num_dim, len, data, stride); 
} 
void tblis_set_vector(tblis_tensor * t, int * dim, int num_dim, void * data){ 
    tblis_init_tensor_s_helper_row_major(t, dim, num_dim, data);
} 

void free_tblis_tensor(tblis_tensor * t){
    free(t->len);
    free(t->stride);
}

void tblis_set_tensor_scalar_s(tblis_tensor *t, float scalar){
    tblis_init_scalar_s(&t->scalar, scalar);
}

#endif

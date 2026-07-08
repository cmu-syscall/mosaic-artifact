// float tblis_vector_dot_transfer(const tblis_comm* comm, const tblis_config* cfg, 
//                     const tblis_vector* A, const tblis_vector* B, 
//                     tblis_scalar* result){ 
//     tblis_vector_dot(comm, cfg, A, B, result); 
//     return result->data.s; } 
void tblis_init_tensor_s_helper_row_major(tblis_tensor * t, int * dim, int num_dim, void * data){ 
    len_type * len = malloc(sizeof(len_type)*num_dim); 
        if (!len){  
        printf("error, len not valid!!!"); 
        } 
    int stride_product = 1;  
    for (int i = 0; i < num_dim; i++){ 
        len[(len_type) i] = dim[i]; 
        stride_product *= dim[i]; 
    } 
    stride_type * stride = malloc(sizeof(stride_type)*num_dim); 
    for (int i = 0; i < num_dim; i++){ 
        stride_product /= dim[i]; 
        stride[(stride_type) i] = stride_product; 
    } 
    tblis_init_tensor_s(t, num_dim, len, data, stride); 
} 
void tblis_set_vector(tblis_tensor * t, int * dim, int num_dim, void * data){ 
    len_type * len = malloc(sizeof(len_type)*num_dim); 
    len[0] = dim[0];
    stride_type * stride = malloc(sizeof(stride_type)*num_dim); 
    stride[0] = 1; 
    tblis_init_tensor_s(t, num_dim, len, data, stride); 
} 

void free_tblis_tensor(tblis_tensor * t){
free(t->len);
free(t->stride);
}
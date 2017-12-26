#include <stdio.h>
#include "graph.h"
// #define TestBit(A,k)    ( A[(k/32)] & (1 << (k%32)) )
// #define ClearBit(A,k)   ( A[(k/32)] &= ~(1 << (k%32)) )
// #define SetBit(A,k)     ( A[(k/32)] |= (1 << (k%32)) )

typedef unsigned int uint;

const uint BITSIZE_PER_THREAD = 4096;
// THREAD_PER_BLOCK = 96

__global__
void printResults(const uint * results, const int nov) {
	const uint vIndex = blockIdx.x * blockDim.x + threadIdx.x;
	if (vIndex == 0) {
		printf("printResults() invoked\n");
		for (int i = 0; i < nov; i++) {
			printf("%d ", results[i]);
		}
		printf("\n");
	}
}

// && results[vIndex] != 0
__global__
void detectConflicts(uint *row_ptr, int *col_ind, uint *results, int nov, uint * errorCode) {
	const uint vIndex = blockIdx.x * blockDim.x + threadIdx.x;
	// 128 int per thread. 128 * 32 = 4096 bit per thread. Total of 8192 int per block.
	__shared__ int forbiddenArray[8192];
	for (size_t i = 0; i < 8192; i++) {
		forbiddenArray[i] = 0;
	}
	__syncthreads();
	if (vIndex < nov) {
		const uint padding = threadIdx.x * 4096; //4096 bit per thread
		for (uint neighborIndex = row_ptr[vIndex]; neighborIndex < row_ptr[vIndex+1]; neighborIndex++) { // distance-1 neighbor loop
			const uint d1neighbor = col_ind[neighborIndex];
			forbiddenArray[((padding + results[d1neighbor])/32)] |= (1 << ((padding + results[d1neighbor])%32));
			for (uint d2neighborIndex = row_ptr[d1neighbor]; d2neighborIndex < row_ptr[d1neighbor + 1]; d2neighborIndex++) {
				if (col_ind[d2neighborIndex] != vIndex) {
					const uint d2neighbor = col_ind[d2neighborIndex];
					forbiddenArray[((padding + results[d2neighbor])/32)] |= (1 << ((padding + results[d2neighbor])%32));
				}
			}
		}
		if (forbiddenArray[((padding + results[vIndex])/32)] & (1 << ((padding + results[vIndex])%32))) {
			atomicAdd(errorCode, 1);
			for (size_t i = 1; i < BITSIZE_PER_THREAD; i++) {
				if (!forbiddenArray[((padding + i)/32)] & (1 << ((padding + i)%32))) {
					results[vIndex] = i;
					break;
				}
			}
		}
		for (size_t i = 0; i < BITSIZE_PER_THREAD; i++) {
			forbiddenArray[((padding + i)/32)] &= ~(1 << ((padding + i)%32));
		}
	}
}
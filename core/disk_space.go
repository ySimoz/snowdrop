package core

import (
	"math"
	"syscall"
)

// checkDiskSpaceAvailable returns true if the filesystem at path has at least requiredBytes free
func checkDiskSpaceAvailable(path string, requiredBytes int64) bool {
	if requiredBytes <= 0 {
		return true
	}
	var stat syscall.Statfs_t
	if err := syscall.Statfs(path, &stat); err != nil {
		return true // If Statfs check fails or path not yet created, allow
	}
	bsize := uint64(stat.Bsize)
	bavail := stat.Bavail
	if bsize > 0 && bavail > math.MaxUint64/bsize {
		return true // Free space exceeds 64-bit uint; plenty of space
	}
	totalFree := bsize * bavail
	if totalFree > math.MaxInt64 {
		return true
	}
	return int64(totalFree) >= requiredBytes
}

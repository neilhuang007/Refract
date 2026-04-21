package at.redi2go.photonics.core.collect;

import it.unimi.dsi.fastutil.longs.Long2ObjectFunction;
import it.unimi.dsi.fastutil.longs.Long2ObjectOpenHashMap;

import java.util.concurrent.locks.ReadWriteLock;
import java.util.concurrent.locks.ReentrantReadWriteLock;
import java.util.function.BiFunction;

public class ConcurrentLong2ObjectMap<V> implements LongObjectMap<V> {
    private final WrapperMap<V>[] maps;
    private final ReadWriteLock[] locks;

    @SuppressWarnings("unchecked")
    public ConcurrentLong2ObjectMap(int numBuckets) {
        this.maps = new WrapperMap[numBuckets];
        this.locks = new ReadWriteLock[numBuckets];
        for (int i = 0; i < numBuckets; i++) {
            maps[i] = new WrapperMap<>();
            locks[i] = new ReentrantReadWriteLock();
        }
    }

    @Override
    public int size() {
        int size = 0;
        for (int i = 0; i < maps.length; i++) {
            var readLock = locks[i].readLock();
            readLock.lock();
            try {
                size += maps[i].size();
            } finally {
                readLock.unlock();
            }
        }
        return size;
    }

    @Override
    public boolean isEmpty() {
        for (int i = 0; i < maps.length; i++) {
            var readLock = locks[i].readLock();
            readLock.lock();
            try {
                if (!maps[i].isEmpty()) {
                    return false;
                }
            } finally {
                readLock.unlock();
            }
        }
        return true;
    }

    @Override
    public boolean containsKey(long key) {
        int bucket = getBucket(key);
        var readLock = locks[bucket].readLock();
        readLock.lock();
        try {
            return maps[bucket].containsKey(key);
        } finally {
            readLock.unlock();
        }
    }

    @Override
    public V get(long key) {
        int bucket = getBucket(key);
        var readLock = locks[bucket].readLock();
        readLock.lock();
        try {
            return maps[bucket].get(key);
        } finally {
            readLock.unlock();
        }
    }

    @Override
    public V put(long key, V value) {
        int bucket = getBucket(key);
        var writeLock = locks[bucket].writeLock();
        writeLock.lock();
        try {
            return maps[bucket].put(key, value);
        } finally {
            writeLock.unlock();
        }
    }

    @Override
    public V remove(long key) {
        int bucket = getBucket(key);
        var writeLock = locks[bucket].writeLock();
        writeLock.lock();
        try {
            return maps[bucket].remove(key);
        } finally {
            writeLock.unlock();
        }
    }

    @Override
    public boolean remove(long key, V value) {
        int bucket = getBucket(key);
        var writeLock = locks[bucket].writeLock();
        writeLock.lock();
        try {
            return maps[bucket].remove(key, value);
        } finally {
            writeLock.unlock();
        }
    }

    @Override
    public V computeIfAbsent(long key, Long2ObjectFunction<V> mappingFunction) {
        int bucket = getBucket(key);
        var writeLock = locks[bucket].writeLock();
        writeLock.lock();
        try {
            return maps[bucket].computeIfAbsent(key, mappingFunction);
        } finally {
            writeLock.unlock();
        }
    }

    @Override
    public V computeIfPresent(long key, BiFunction<Long, V, V> mappingFunction) {
        int bucket = getBucket(key);
        var writeLock = locks[bucket].writeLock();
        writeLock.lock();
        try {
            return maps[bucket].computeIfPresent(key, mappingFunction);
        } finally {
            writeLock.unlock();
        }
    }

    private int getBucket(long key) {
        return Math.floorMod(Long.hashCode(key), maps.length);
    }

    private static class WrapperMap<V> extends Long2ObjectOpenHashMap<V> {
    }
}

package at.redi2go.photonics.core.collect;

import it.unimi.dsi.fastutil.ints.Int2ObjectFunction;

import java.util.function.BiFunction;

public interface IntObjectMap<V> {
    int size();

    boolean isEmpty();

    boolean containsKey(int key);

    V get(int key);

    V put(int key, V value);

    V remove(int key);

    boolean remove(int key, V value);

    V computeIfAbsent(int key, Int2ObjectFunction<V> mappingFunction);

    V computeIfPresent(int key, BiFunction<Integer, V, V> mappingFunction);
}

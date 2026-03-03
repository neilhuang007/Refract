package at.redi2go.photonic.client.rendering.util;

import at.redi2go.photonic.client.PhotonicsStorage;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.function.Consumer;

public class MultiThreader {
   public static final int DEFAULT_THREAD_COUNT = Math.max(Runtime.getRuntime().availableProcessors() / 2, 1);
   private static final ExecutorService MULTI_THREAD_SERVICE = Executors.newFixedThreadPool(DEFAULT_THREAD_COUNT, MultiThreader.CallAwareThread::new);
   private static final ExecutorService SINGLE_THREAD_SERVICE = Executors.newSingleThreadExecutor(MultiThreader.CallAwareThread::new);
   private static ExecutorService EXECUTOR_SERVICE = SINGLE_THREAD_SERVICE;

   public static void runAndWait(int dispatchCount, Consumer<Integer> consumer) {
      try {
         run(dispatchCount, consumer).get();
      } catch (ExecutionException | InterruptedException var3) {
         throw new RuntimeException(var3);
      }
   }

   public static CompletableFuture<Void> run(int dispatchCount, Consumer<Integer> consumer) {
      if (Thread.currentThread() instanceof MultiThreader.CallAwareThread) {
         new IllegalStateException().printStackTrace();
      }

      CompletableFuture<?>[] completableFutures = new CompletableFuture[dispatchCount];

      for (int i = 0; i < dispatchCount; i++) {
         int finalI = i;
         completableFutures[i] = CompletableFuture.runAsync(() -> consumer.accept(finalI), EXECUTOR_SERVICE);
      }

      return CompletableFuture.allOf(completableFutures);
   }

   public static boolean getMultiThreading() {
      return EXECUTOR_SERVICE == MULTI_THREAD_SERVICE;
   }

   public static void setMultiThreading(boolean multiThreading) {
      if (multiThreading) {
         EXECUTOR_SERVICE = MULTI_THREAD_SERVICE;
      } else {
         EXECUTOR_SERVICE = SINGLE_THREAD_SERVICE;
      }
   }

   static {
      PhotonicsStorage.Parameter<Boolean> doMultithreadingParameter = PhotonicsStorage.DO_MULTITHREADING;
      setMultiThreading(doMultithreadingParameter.value);
      doMultithreadingParameter.addObserver(MultiThreader::setMultiThreading);
   }

   private static class CallAwareThread extends Thread {
      public CallAwareThread(Runnable target) {
         super(target, "WorldCompileWorker " + UUID.randomUUID());
      }
   }
}

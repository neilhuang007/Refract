package at.redi2go.photonic.client.config;

import java.util.Optional;

class PhotonicsConfigOwner implements Variable.Owner {
   static final PhotonicsConfigOwner INSTANCE = new PhotonicsConfigOwner();

   private PhotonicsConfigOwner() {
   }

   @Override
   public int mod() {
      return PhotonicsConfig.mod;
   }

   @Override
   public <T> Optional<T> getValue(Variable.Type<T> type, String name) {
      return PhotonicsConfig.INSTANCE.defines.getValue(type, name);
   }
}

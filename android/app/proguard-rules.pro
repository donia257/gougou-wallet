# ML Kit discovers these registrars by manifest metadata and invokes their
# no-argument constructors reflectively. R8 full mode must retain constructors.
-keep class * implements com.google.firebase.components.ComponentRegistrar {
    public <init>();
}

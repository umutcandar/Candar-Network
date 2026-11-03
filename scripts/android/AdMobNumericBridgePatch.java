import java.nio.file.*;
import org.objectweb.asm.*;

/** Preserve the vendor ABI while accepting both JNI Integer and Long values. */
public final class AdMobNumericBridgePatch {
    public static void main(String[] args) throws Exception {
        ClassReader reader = new ClassReader(Files.readAllBytes(Path.of(args[0])));
        ClassWriter writer = new ClassWriter(reader, 0);
        int[] counts = {0, 0};
        reader.accept(new ClassVisitor(Opcodes.ASM9, writer) {
            @Override public MethodVisitor visitMethod(int access, String name, String desc,
                                                       String signature, String[] exceptions) {
                MethodVisitor original = super.visitMethod(access, name, desc, signature, exceptions);
                if (!name.equals(args[2])) return original;
                return new MethodVisitor(Opcodes.ASM9, original) {
                    @Override public void visitTypeInsn(int opcode, String type) {
                        if (opcode == Opcodes.CHECKCAST && type.equals("java/lang/Integer")) {
                            type = "java/lang/Number";
                            counts[0]++;
                        }
                        super.visitTypeInsn(opcode, type);
                    }
                    @Override public void visitMethodInsn(int opcode, String owner, String name,
                                                          String descriptor, boolean isInterface) {
                        if (opcode == Opcodes.INVOKEVIRTUAL && owner.equals("java/lang/Integer")
                                && name.equals("intValue") && descriptor.equals("()I")) {
                            owner = "java/lang/Number";
                            counts[1]++;
                        }
                        super.visitMethodInsn(opcode, owner, name, descriptor, isInterface);
                    }
                };
            }
        }, 0);
        int expected = Integer.parseInt(args[3]);
        if (counts[0] != expected || counts[1] != expected)
            throw new IllegalStateException("Unexpected vendor bytecode: " + counts[0] + "/" + counts[1]);
        Files.write(Path.of(args[1]), writer.toByteArray());
        System.out.println(args[2] + ": verified " + expected + " numeric conversions");
    }
}

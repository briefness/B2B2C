import com.android.build.gradle.AppExtension

val android = project.extensions.getByType(AppExtension::class.java)

android.apply {
    flavorDimensions("flavor-type")

    productFlavors {
        create("customerA") {
            dimension = "flavor-type"
            applicationId = "com.b2b2c.wallet.customerA"
            resValue(type = "string", name = "app_name", value = "Customer A Wallet")
        }
        create("customerB") {
            dimension = "flavor-type"
            applicationId = "com.b2b2c.wallet.customerB"
            resValue(type = "string", name = "app_name", value = "Customer B Wallet")
        }
        create("customerC") {
            dimension = "flavor-type"
            applicationId = "com.b2b2c.wallet.customerC"
            resValue(type = "string", name = "app_name", value = "Customer C Wallet")
        }
    }

    buildFeatures.resValues = true
}
#include <vtkActor.h>
#include <vtkBoxRepresentation.h>
#include <vtkBoxWidget2.h>
#include <vtkCamera.h>
#include <vtkColorTransferFunction.h>
#include <vtkCommand.h>
#include <vtkGPUVolumeRayCastMapper.h>
#include <vtkImageData.h>
#include <vtkInteractorStyleTrackballCamera.h>
#include <vtkNew.h>
#include <vtkObjectFactory.h>
#include <vtkOpenGLGPUVolumeRayCastMapper.h>
#include <vtkPiecewiseFunction.h>
#include <vtkPlane.h>
#include <vtkPlaneCollection.h>
#include <vtkPlanes.h>
#include <vtkProperty.h>
#include <vtkRenderWindow.h>
#include <vtkRenderWindowInteractor.h>
#include <vtkRenderer.h>
#include <vtkVolume.h>
#include <vtkVolumeProperty.h>
#include <vtkXMLImageDataReader.h>
#include <vtkMatrix4x4.h>
#include <vtkSmartVolumeMapper.h>

// #include "FragmentShader.h"
#include "ComputeGradient.h"

class vtkBoxCallback : public vtkCommand
{
public:
  static vtkBoxCallback* New()
  {
    return new vtkBoxCallback;
  }

  vtkBoxCallback()
  {
    this->Mapper = nullptr;
    this->Interactor = nullptr;
  }

  virtual void Execute(vtkObject* caller, unsigned long, void*)
  {
    if (!this->Mapper || !this->Interactor)
    {
      return;
    }
    vtkBoxWidget2* boxWidget = reinterpret_cast<vtkBoxWidget2*>(caller);
    vtkBoxRepresentation* boxRep =
      vtkBoxRepresentation::SafeDownCast(boxWidget->GetRepresentation());
    vtkNew<vtkPlanes> boxPlanes;
    boxRep->GetPlanes(boxPlanes);
    vtkNew<vtkPlaneCollection> clippingPlanes;
    for (int i = 0; i < boxPlanes->GetNumberOfPlanes(); ++i)
    {
      clippingPlanes->AddItem(boxPlanes->GetPlane(i));
    }
    this->Mapper->SetClippingPlanes(boxPlanes);
    this->Interactor->Render();
  }

  vtkGPUVolumeRayCastMapper* Mapper;
  vtkRenderWindowInteractor* Interactor;
};

class vtkCustomInteractorStyle : public vtkInteractorStyleTrackballCamera
{
public:
  static vtkCustomInteractorStyle* New();
  vtkTypeMacro(vtkCustomInteractorStyle, vtkInteractorStyleTrackballCamera);

  virtual void OnKeyPress() override
    {
    std::string key = this->Interactor->GetKeySym();
    if (key == "c")
      {
      if (this->GPUMapper)
        {
        this->Mapper->SetRequestedRenderModeToRayCast();
        this->GPUMapper = false;
        }
      else
        {
        this->Mapper->SetRequestedRenderModeToGPU();
        this->GPUMapper = true;
        }
      this->Interactor->Render();
      }
    // Forward events
    vtkInteractorStyleTrackballCamera::OnKeyPress();
    }

  // virtual void OnKeyPress() override
  // {
  //   // Get the keypress
  //   std::string key = this->Interactor->GetKeySym();
  //   if (key == "c")
  //   {
  //     if (this->Replacement)
  //     {
  //       // this->Mapper->ClearAllShaderReplacements();
  //       this->Replacement = false;
  //     }
  //     else
  //     {
  //       this->Mapper->AddShaderReplacement(vtkShader::Fragment,
  //                                          "//VTK::ComputeGradient::Dec",
  //                                          true,
  //                                          ComputeGradient,
  //                                          true);
  //       this->Replacement = true;
  //     }
  //     this->Interactor->Render();
  //   }

  //   // Forward events
  //   vtkInteractorStyleTrackballCamera::OnKeyPress();
  // }

  vtkCustomInteractorStyle()
  {
    // this->Replacement = true;
    this->Mapper = nullptr;
    this->GPUMapper = true;
  }

  vtkSmartVolumeMapper* Mapper;
  // bool Replacement;
  bool GPUMapper;
};
vtkStandardNewMacro(vtkCustomInteractorStyle);

int main(int argc, char* argv[])
{
  if (argc < 2)
  {
    std::cerr << "Usage: " << argv[0] << " <input nrrd file>" << std::endl;
    return EXIT_FAILURE;
  }

  vtkNew<vtkXMLImageDataReader> reader;
  reader->SetFileName(argv[1]);
  reader->Update();
  vtkImageData* data = reader->GetOutput();
  data->SetOrigin(0, 0, 0);
  data->SetSpacing(1, 1, 1);
  double* bounds = data->GetBounds();

  vtkNew<vtkSmartVolumeMapper> mapper;
  mapper->SetInputData(data);
  // mapper->SetInputConnection(reader->GetOutputPort());
  // mapper->SetUseJittering(0);

  vtkNew<vtkColorTransferFunction> ctf;
  ctf->AddRGBPoint(-1024, 0.0, 0.0, 0.0);
  ctf->AddRGBPoint(-649, 0.25, 0.25, 0.25);
  ctf->AddRGBPoint(-291, 0.5, 0.5, 0.5);
  ctf->AddRGBPoint(67, 0.75, 0.75, 0.75);
  ctf->AddRGBPoint(419, 1.0, 1.0, 1.0);

  vtkNew<vtkPiecewiseFunction> pf;
  pf->AddPoint(-2048, 0.0);
  pf->AddPoint(-1024, 0.0);
  pf->AddPoint(419, 1.0);

  vtkNew<vtkVolumeProperty> prop;
  prop->SetColor(ctf);
  prop->SetScalarOpacity(pf);
  prop->SetShade(1);

  double elements[16] = {
   -0.933594, 0, 0, 238.533,
  0, -0.933594, 0, 238.533,
  0, 0, 1.25, -200,
  0, 0, 0, 1
  };

  vtkNew<vtkMatrix4x4> matrix;
  matrix->DeepCopy(elements);

  vtkNew<vtkVolume> volume;
  volume->SetMapper(mapper);
  volume->SetProperty(prop);
  volume->PokeMatrix(matrix);

  // vtkOpenGLGPUVolumeRayCastMapper* glMapper =
  //   vtkOpenGLGPUVolumeRayCastMapper::SafeDownCast(mapper);
  // mapper->SetBlendModeToMaximumIntensity();
  // glMapper->AddShaderReplacement(vtkShader::Fragment,
  //                                "//VTK::ComputeGradient::Dec",
  //                                true,
  //                                ComputeGradient,
  //                                true);

  vtkNew<vtkRenderWindow> renWin;
  renWin->SetMultiSamples(0);
  renWin->SetSize(801, 800);

  vtkNew<vtkRenderer> ren;
  ren->SetBackground(0.23, 0.23, 0.33);
  renWin->AddRenderer(ren.GetPointer());

  vtkNew<vtkRenderWindowInteractor> iren;
  iren->SetRenderWindow(renWin.GetPointer());
  vtkNew<vtkCustomInteractorStyle> style;
  // vtkNew<vtkInteractorStyleTrackballCamera> style;
  style->Mapper = mapper.GetPointer();
  iren->SetInteractorStyle(style);

  ren->AddVolume(volume);
  ren->ResetCamera();

  // vtkNew<vtkBoxRepresentation> boxRep;
  // boxRep->InsideOutOn();
  // vtkNew<vtkBoxWidget2> boxWidget;
  // boxWidget->SetRepresentation(boxRep);
  // boxWidget->SetInteractor(iren);
  // vtkNew<vtkBoxCallback> cbk;
  // cbk->Mapper = mapper.GetPointer();
  // cbk->Interactor = iren.GetPointer();
  // boxWidget->AddObserver(vtkCommand::InteractionEvent, cbk);

  // ren->GetActiveCamera()->Zoom(1.5);
  // ren->GetActiveCamera()->Roll(-70);
  // ren->GetActiveCamera()->Azimuth(90);
  // ren->GetActiveCamera()->SetViewAngle(170);
  // ren->GetActiveCamera()->SetViewUp(0, 0, 1);
  // ren->GetActiveCamera()->Dolly(2);
  // ren->GetActiveCamera()->ParallelProjectionOn();

  renWin->Render();

  // double * range = ren->GetActiveCamera()->GetClippingRange();
  // std::cout << range[0] << " " << range[1] << std::endl;
  // range[0] = 1.06;//1102.07;
  // range[1] = 1061;//2038.95;
  // renWin->Render()
  // boxRep->PlaceWidget(bounds);
  // boxRep->SetPlaceFactor(1.0);
  // vtkProperty* handleProp = boxRep->GetHandleProperty();
  // handleProp->SetColor(0.31, 0.38, 0.56);
  // handleProp->SetAmbient(0.5);
  // handleProp->SetSpecularColor(0.47, 0.53, 0.67);
  // handleProp->SetSpecularPower(100);
  // vtkProperty* selHandleProp = boxRep->GetSelectedHandleProperty();
  // selHandleProp->SetColor(0.6, 0.2, 0.32);
  // selHandleProp->SetAmbient(0.5);
  // selHandleProp->SetSpecularColor(0.9, 0.63, 0.71);
  // selHandleProp->SetSpecularPower(100);
  // vtkProperty* faceProp = boxRep->GetSelectedFaceProperty();
  // faceProp->SetColor(0.5, 0.71, 0.4);
  // boxWidget->On();
  // cbk->Execute(boxWidget, 0, nullptr);

  iren->Start();

  return EXIT_SUCCESS;
}

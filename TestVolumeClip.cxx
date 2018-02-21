#include <vtkActor.h>
#include <vtkBoxRepresentation.h>
#include <vtkBoxWidget2.h>
#include <vtkCamera.h>
#include <vtkColorTransferFunction.h>
#include <vtkCommand.h>
#include <vtkGPUVolumeRayCastMapper.h>
#include <vtkImageData.h>
#include <vtkNew.h>
#include <vtkOpenGLGPUVolumeRayCastMapper.h>
#include <vtkPiecewiseFunction.h>
#include <vtkPlane.h>
#include <vtkPlaneCollection.h>
#include <vtkPlanes.h>
#include <vtkRenderWindow.h>
#include <vtkRenderWindowInteractor.h>
#include <vtkRenderer.h>
#include <vtkVolume.h>
#include <vtkVolumeProperty.h>
#include <vtkXMLImageDataReader.h>

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
    vtkBoxRepresentation* rep =
      vtkBoxRepresentation::SafeDownCast(boxWidget->GetRepresentation());
    vtkNew<vtkPlanes> boxPlanes;
    rep->GetPlanes(boxPlanes);
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

  vtkNew<vtkGPUVolumeRayCastMapper> mapper;
  mapper->SetInputConnection(reader->GetOutputPort());
  mapper->SetUseJittering(1);

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

  vtkNew<vtkVolume> volume;
  volume->SetMapper(mapper);
  volume->SetProperty(prop);

  double* bounds = vtkImageData::SafeDownCast(reader->GetOutput())->GetBounds();
  vtkOpenGLGPUVolumeRayCastMapper* glMapper =
    vtkOpenGLGPUVolumeRayCastMapper::SafeDownCast(mapper);
  glMapper->AddShaderReplacement(vtkShader::Fragment,
                                 "//VTK::ComputeGradient::Dec",
                                 true,
                                 ComputeGradient,
                                 true);

  vtkNew<vtkRenderWindow> renWin;
  renWin->SetMultiSamples(0);
  renWin->SetSize(801, 800);

  vtkNew<vtkRenderer> ren;
  renWin->AddRenderer(ren.GetPointer());

  vtkNew<vtkRenderWindowInteractor> iren;
  iren->SetRenderWindow(renWin.GetPointer());

  ren->AddVolume(volume);
  ren->ResetCamera();

  vtkNew<vtkBoxRepresentation> boxRep;
  boxRep->InsideOutOn();
  vtkNew<vtkBoxWidget2> boxWidget;
  boxWidget->SetRepresentation(boxRep);
  boxWidget->SetInteractor(iren);
  vtkNew<vtkBoxCallback> cbk;
  cbk->Mapper = mapper.GetPointer();
  cbk->Interactor = iren.GetPointer();
  boxWidget->AddObserver(vtkCommand::InteractionEvent, cbk);

  ren->GetActiveCamera()->Zoom(1.5);
  ren->GetActiveCamera()->Roll(-70);
  ren->GetActiveCamera()->Azimuth(90);

  renWin->Render();

  boxRep->PlaceWidget(bounds);
  boxWidget->On();
  cbk->Execute(boxWidget, 0, nullptr);

  iren->Start();

  return EXIT_SUCCESS;
}
